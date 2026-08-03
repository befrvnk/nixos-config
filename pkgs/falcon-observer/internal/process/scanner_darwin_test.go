//go:build darwin && cgo

package process

import (
	"encoding/binary"
	"os"
	"reflect"
	"testing"
)

func TestParseProcArgs(t *testing.T) {
	buffer := make([]byte, 4)
	binary.LittleEndian.PutUint32(buffer, 3)
	buffer = append(buffer, []byte("/usr/bin/java\x00\x00")...)
	buffer = append(buffer, []byte("java\x00org.gradle.wrapper.GradleWrapperMain\x00assembleDebug\x00")...)

	got := parseProcArgs(buffer)
	want := []string{"java", "org.gradle.wrapper.GradleWrapperMain", "assembleDebug"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("parseProcArgs() = %#v, want %#v", got, want)
	}
}

func TestDarwinScannerFindsCurrentProcess(t *testing.T) {
	processes, err := (DarwinScanner{}).Scan()
	if err != nil {
		t.Fatal(err)
	}
	for _, current := range processes {
		if current.PID == os.Getpid() {
			if current.StartTime == 0 || current.Name == "" || current.TotalCPUNanos() == 0 {
				t.Fatalf("current process has incomplete metrics: %#v", current)
			}
			return
		}
	}
	t.Fatal("scanner did not return the current process")
}
