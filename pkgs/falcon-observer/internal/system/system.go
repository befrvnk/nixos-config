package system

import "time"

type Counters struct {
	At              time.Time `json:"at"`
	CPUUserTicks    uint64    `json:"-"`
	CPUSystemTicks  uint64    `json:"-"`
	CPUNiceTicks    uint64    `json:"-"`
	CPUIdleTicks    uint64    `json:"-"`
	FreeBytes       uint64    `json:"free_bytes"`
	ActiveBytes     uint64    `json:"active_bytes"`
	InactiveBytes   uint64    `json:"inactive_bytes"`
	WiredBytes      uint64    `json:"wired_bytes"`
	CompressedBytes uint64    `json:"compressed_bytes"`
	SwapUsedBytes   uint64    `json:"swap_used_bytes"`
	SwapTotalBytes  uint64    `json:"swap_total_bytes"`
}

type Sample struct {
	At               time.Time `json:"at"`
	CPUUserPercent   float64   `json:"cpu_user_percent,omitempty"`
	CPUSystemPercent float64   `json:"cpu_system_percent,omitempty"`
	CPUIdlePercent   float64   `json:"cpu_idle_percent,omitempty"`
	FreeBytes        uint64    `json:"free_bytes"`
	ActiveBytes      uint64    `json:"active_bytes"`
	InactiveBytes    uint64    `json:"inactive_bytes"`
	WiredBytes       uint64    `json:"wired_bytes"`
	CompressedBytes  uint64    `json:"compressed_bytes"`
	SwapUsedBytes    uint64    `json:"swap_used_bytes"`
	SwapTotalBytes   uint64    `json:"swap_total_bytes"`
}

type Tracker struct {
	previous *Counters
}

func (tracker *Tracker) Calculate(current Counters) Sample {
	sample := Sample{
		At:              current.At,
		FreeBytes:       current.FreeBytes,
		ActiveBytes:     current.ActiveBytes,
		InactiveBytes:   current.InactiveBytes,
		WiredBytes:      current.WiredBytes,
		CompressedBytes: current.CompressedBytes,
		SwapUsedBytes:   current.SwapUsedBytes,
		SwapTotalBytes:  current.SwapTotalBytes,
	}
	if tracker.previous != nil {
		previous := tracker.previous
		user := delta(current.CPUUserTicks, previous.CPUUserTicks) + delta(current.CPUNiceTicks, previous.CPUNiceTicks)
		system := delta(current.CPUSystemTicks, previous.CPUSystemTicks)
		idle := delta(current.CPUIdleTicks, previous.CPUIdleTicks)
		total := user + system + idle
		if total > 0 {
			sample.CPUUserPercent = float64(user) / float64(total) * 100
			sample.CPUSystemPercent = float64(system) / float64(total) * 100
			sample.CPUIdlePercent = float64(idle) / float64(total) * 100
		}
	}
	copy := current
	tracker.previous = &copy
	return sample
}

func delta(current, previous uint64) uint64 {
	if current < previous {
		return 0
	}
	return current - previous
}
