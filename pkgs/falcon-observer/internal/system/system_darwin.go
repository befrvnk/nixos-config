//go:build darwin && cgo

package system

/*
#include <mach/host_info.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <stdint.h>
#include <string.h>
#include <sys/sysctl.h>

struct fo_system_counters {
	uint64_t cpu_user;
	uint64_t cpu_system;
	uint64_t cpu_nice;
	uint64_t cpu_idle;
	uint64_t free_bytes;
	uint64_t active_bytes;
	uint64_t inactive_bytes;
	uint64_t wired_bytes;
	uint64_t compressed_bytes;
	uint64_t swap_used_bytes;
	uint64_t swap_total_bytes;
};

static int fo_system_snapshot(struct fo_system_counters *result) {
	memset(result, 0, sizeof(*result));
	mach_port_t host = mach_host_self();

	host_cpu_load_info_data_t cpu;
	mach_msg_type_number_t cpu_count = HOST_CPU_LOAD_INFO_COUNT;
	if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &cpu_count) != KERN_SUCCESS) {
		return -1;
	}
	result->cpu_user = cpu.cpu_ticks[CPU_STATE_USER];
	result->cpu_system = cpu.cpu_ticks[CPU_STATE_SYSTEM];
	result->cpu_nice = cpu.cpu_ticks[CPU_STATE_NICE];
	result->cpu_idle = cpu.cpu_ticks[CPU_STATE_IDLE];

	vm_statistics64_data_t vm;
	mach_msg_type_number_t vm_count = HOST_VM_INFO64_COUNT;
	if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &vm_count) != KERN_SUCCESS) {
		return -1;
	}
	vm_size_t page_size = 0;
	if (host_page_size(host, &page_size) != KERN_SUCCESS) {
		return -1;
	}
	result->free_bytes = (uint64_t)vm.free_count * page_size;
	result->active_bytes = (uint64_t)vm.active_count * page_size;
	result->inactive_bytes = (uint64_t)vm.inactive_count * page_size;
	result->wired_bytes = (uint64_t)vm.wire_count * page_size;
	result->compressed_bytes = (uint64_t)vm.compressor_page_count * page_size;

	struct xsw_usage swap;
	size_t swap_size = sizeof(swap);
	if (sysctlbyname("vm.swapusage", &swap, &swap_size, NULL, 0) == 0) {
		result->swap_used_bytes = swap.xsu_used;
		result->swap_total_bytes = swap.xsu_total;
	}
	return 0;
}
*/
import "C"

import (
	"fmt"
	"time"
)

func Snapshot() (Counters, error) {
	var raw C.struct_fo_system_counters
	if C.fo_system_snapshot(&raw) != 0 {
		return Counters{}, fmt.Errorf("collect Mach host statistics")
	}
	return Counters{
		At:              time.Now(),
		CPUUserTicks:    uint64(raw.cpu_user),
		CPUSystemTicks:  uint64(raw.cpu_system),
		CPUNiceTicks:    uint64(raw.cpu_nice),
		CPUIdleTicks:    uint64(raw.cpu_idle),
		FreeBytes:       uint64(raw.free_bytes),
		ActiveBytes:     uint64(raw.active_bytes),
		InactiveBytes:   uint64(raw.inactive_bytes),
		WiredBytes:      uint64(raw.wired_bytes),
		CompressedBytes: uint64(raw.compressed_bytes),
		SwapUsedBytes:   uint64(raw.swap_used_bytes),
		SwapTotalBytes:  uint64(raw.swap_total_bytes),
	}, nil
}
