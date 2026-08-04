//go:build darwin && cgo

package process

/*
#cgo LDFLAGS: -lproc
#include <libproc.h>
#include <mach/mach_time.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/resource.h>
#include <sys/sysctl.h>

struct fo_proc_info {
	int pid;
	int ppid;
	uint32_t uid;
	uint64_t start_sec;
	uint64_t start_usec;
	uint64_t user_nanos;
	uint64_t system_nanos;
	uint64_t resident_bytes;
	uint64_t read_bytes;
	uint64_t written_bytes;
	char name[2 * MAXCOMLEN];
};

static uint64_t fo_absolute_to_nanos(uint64_t value) {
	mach_timebase_info_data_t info;
	if (mach_timebase_info(&info) != KERN_SUCCESS || info.denom == 0) {
		return value;
	}
	// Divide before multiplying where possible to avoid overflowing long-lived
	// process counters while retaining the remainder's precision.
	return (value / info.denom) * info.numer +
	       ((value % info.denom) * info.numer) / info.denom;
}

static int fo_list_pids(int *buffer, int buffer_bytes) {
	return proc_listallpids(buffer, buffer_bytes);
}

static int fo_proc_info_for_pid(int pid, struct fo_proc_info *result) {
	struct proc_taskallinfo info;
	memset(&info, 0, sizeof(info));
	int size = proc_pidinfo(pid, PROC_PIDTASKALLINFO, 0, &info, sizeof(info));
	if (size != sizeof(info)) {
		return -1;
	}

	memset(result, 0, sizeof(*result));
	result->pid = pid;
	result->ppid = (int)info.pbsd.pbi_ppid;
	result->uid = (uint32_t)info.pbsd.pbi_uid;
	result->start_sec = info.pbsd.pbi_start_tvsec;
	result->start_usec = info.pbsd.pbi_start_tvusec;
	result->user_nanos = info.ptinfo.pti_total_user;
	result->system_nanos = info.ptinfo.pti_total_system;
	result->resident_bytes = info.ptinfo.pti_resident_size;

	const char *name = info.pbsd.pbi_name[0] != '\0' ? info.pbsd.pbi_name : info.pbsd.pbi_comm;
	strlcpy(result->name, name, sizeof(result->name));
	return 0;
}

static int fo_proc_path(int pid, char *buffer, uint32_t size) {
	return proc_pidpath(pid, buffer, size);
}

static int fo_proc_cwd(int pid, char *buffer, uint32_t size) {
	struct proc_vnodepathinfo info;
	memset(&info, 0, sizeof(info));
	int result = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, sizeof(info));
	if (result != sizeof(info)) {
		return -1;
	}
	strlcpy(buffer, info.pvi_cdir.vip_path, size);
	return buffer[0] == '\0' ? -1 : 0;
}

static int fo_proc_rusage_for_pid(int pid, struct fo_proc_info *result) {
	struct rusage_info_v4 usage;
	memset(&usage, 0, sizeof(usage));
	if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&usage) != 0) {
		return -1;
	}
	// rusage CPU counters use mach_absolute_time units, not nanoseconds.
	result->user_nanos = fo_absolute_to_nanos(usage.ri_user_time);
	result->system_nanos = fo_absolute_to_nanos(usage.ri_system_time);
	result->resident_bytes = usage.ri_resident_size;
	result->read_bytes = usage.ri_diskio_bytesread;
	result->written_bytes = usage.ri_diskio_byteswritten;
	return 0;
}

static int fo_argmax(void) {
	int value = 0;
	size_t size = sizeof(value);
	if (sysctlbyname("kern.argmax", &value, &size, NULL, 0) != 0 || value <= 0) {
		return 1048576;
	}
	return value;
}

static int fo_proc_args(int pid, char *buffer, size_t *size) {
	int mib[3] = { CTL_KERN, KERN_PROCARGS2, pid };
	return sysctl(mib, 3, buffer, size, NULL, 0);
}
*/
import "C"

import (
	"encoding/binary"
	"fmt"
	"path/filepath"
	"strings"
	"unsafe"
)

type DarwinScanner struct{}

func (DarwinScanner) Scan() ([]Process, error) {
	count := int(C.fo_list_pids(nil, 0))
	if count <= 0 {
		return nil, fmt.Errorf("proc_listallpids returned %d", count)
	}

	pids := make([]C.int, count+128)
	count = int(C.fo_list_pids((*C.int)(unsafe.Pointer(&pids[0])), C.int(len(pids)*int(unsafe.Sizeof(pids[0])))))
	if count < 0 {
		return nil, fmt.Errorf("proc_listallpids failed")
	}
	if count > len(pids) {
		count = len(pids)
	}

	result := make([]Process, 0, count)
	for _, rawPID := range pids[:count] {
		pid := int(rawPID)
		if pid <= 0 {
			continue
		}
		var info C.struct_fo_proc_info
		if C.fo_proc_info_for_pid(C.int(pid), &info) != 0 {
			continue
		}

		current := Process{
			Identity: Identity{
				PID:       pid,
				StartTime: uint64(info.start_sec)*1_000_000_000 + uint64(info.start_usec)*1_000,
			},
			PPID:          int(info.ppid),
			UID:           uint32(info.uid),
			Name:          C.GoString(&info.name[0]),
			UserNanos:     uint64(info.user_nanos),
			SystemNanos:   uint64(info.system_nanos),
			ResidentBytes: uint64(info.resident_bytes),
		}
		if needsDetails(current) {
			var path [C.PROC_PIDPATHINFO_MAXSIZE]C.char
			if C.fo_proc_path(C.int(pid), &path[0], C.uint32_t(len(path))) > 0 {
				current.Path = C.GoString(&path[0])
			}
			var cwd [C.PROC_PIDPATHINFO_MAXSIZE]C.char
			if C.fo_proc_cwd(C.int(pid), &cwd[0], C.uint32_t(len(cwd))) == 0 {
				current.WorkingDirectory = C.GoString(&cwd[0])
			}
			if C.fo_proc_rusage_for_pid(C.int(pid), &info) == 0 {
				current.UserNanos = uint64(info.user_nanos)
				current.SystemNanos = uint64(info.system_nanos)
				current.ResidentBytes = uint64(info.resident_bytes)
				current.ReadBytes = uint64(info.read_bytes)
				current.WrittenBytes = uint64(info.written_bytes)
			}
		}
		if needsArguments(current) {
			current.Args = readArguments(pid)
		}
		result = append(result, current)
	}
	return result, nil
}

func needsDetails(current Process) bool {
	return isCandidateName(strings.ToLower(current.Name))
}

func needsArguments(current Process) bool {
	return isCandidateName(strings.ToLower(current.Name)) || isCandidateName(strings.ToLower(filepath.Base(current.Path)))
}

func isCandidateName(candidate string) bool {
	for _, name := range buildProcessNames {
		if candidate == name {
			return true
		}
	}
	return strings.Contains(candidate, "crowdstrike") ||
		strings.Contains(candidate, "falcon") ||
		strings.Contains(candidate, "gradle") ||
		strings.Contains(candidate, "kotlin") ||
		strings.Contains(candidate, "swiftc")
}

var buildProcessNames = []string{
	"aapt2", "bun", "c++", "cargo", "cc", "clang", "clang++", "cmake", "d8",
	"gmake", "go", "gradle", "gradlew", "java", "kotlin", "make", "ninja", "nix",
	"node", "npm", "npx", "pnpm", "r8", "rustc", "swift", "swiftc", "tsc",
	"xcodebuild", "yarn",
}

func readArguments(pid int) []string {
	size := int(C.fo_argmax())
	if size <= 0 {
		return nil
	}
	buffer := make([]byte, size)
	actual := C.size_t(size)
	if C.fo_proc_args(C.int(pid), (*C.char)(unsafe.Pointer(&buffer[0])), &actual) != 0 {
		return nil
	}
	return parseProcArgs(buffer[:int(actual)])
}

func parseProcArgs(buffer []byte) []string {
	if len(buffer) < 4 {
		return nil
	}
	argc := int(int32(binary.LittleEndian.Uint32(buffer[:4])))
	if argc <= 0 {
		return nil
	}

	position := 4
	for position < len(buffer) && buffer[position] != 0 {
		position++
	}
	for position < len(buffer) && buffer[position] == 0 {
		position++
	}

	arguments := make([]string, 0, argc)
	for position < len(buffer) && len(arguments) < argc {
		end := position
		for end < len(buffer) && buffer[end] != 0 {
			end++
		}
		if end > position {
			arguments = append(arguments, string(buffer[position:end]))
		}
		position = end + 1
	}
	return arguments
}

func absoluteToNanos(value uint64) uint64 {
	return uint64(C.fo_absolute_to_nanos(C.uint64_t(value)))
}
