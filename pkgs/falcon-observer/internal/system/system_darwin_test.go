//go:build darwin && cgo

package system

import "testing"

func TestSnapshotReturnsHostMetrics(t *testing.T) {
	counters, err := Snapshot()
	if err != nil {
		t.Fatal(err)
	}
	if counters.At.IsZero() {
		t.Fatal("snapshot timestamp is zero")
	}
	if counters.CPUUserTicks+counters.CPUSystemTicks+counters.CPUIdleTicks == 0 {
		t.Fatal("snapshot contains no CPU ticks")
	}
	if counters.FreeBytes+counters.ActiveBytes+counters.InactiveBytes+counters.WiredBytes == 0 {
		t.Fatal("snapshot contains no memory counters")
	}
}
