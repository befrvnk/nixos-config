package process

import "time"

type Identity struct {
	PID       int    `json:"pid"`
	StartTime uint64 `json:"start_time_unix_nano"`
}

type Process struct {
	Identity
	PPID             int      `json:"ppid"`
	UID              uint32   `json:"uid"`
	Name             string   `json:"name"`
	Path             string   `json:"path,omitempty"`
	Args             []string `json:"-"`
	WorkingDirectory string   `json:"-"`
	UserNanos        uint64   `json:"user_nanos"`
	SystemNanos      uint64   `json:"system_nanos"`
	ResidentBytes    uint64   `json:"resident_bytes"`
	ReadBytes        uint64   `json:"read_bytes"`
	WrittenBytes     uint64   `json:"written_bytes"`
}

func (process Process) TotalCPUNanos() uint64 {
	return process.UserNanos + process.SystemNanos
}

type Scanner interface {
	Scan() ([]Process, error)
}

type CPUTracker struct {
	previous   map[Identity]uint64
	previousAt time.Time
}

func NewCPUTracker() *CPUTracker {
	return &CPUTracker{previous: make(map[Identity]uint64)}
}

func (tracker *CPUTracker) Calculate(now time.Time, processes []Process) map[Identity]float64 {
	result := make(map[Identity]float64, len(processes))
	elapsed := now.Sub(tracker.previousAt)
	for _, current := range processes {
		total := current.TotalCPUNanos()
		if previous, exists := tracker.previous[current.Identity]; exists && elapsed > 0 && total >= previous {
			result[current.Identity] = float64(total-previous) / float64(elapsed.Nanoseconds()) * 100
		}
	}

	tracker.previous = make(map[Identity]uint64, len(processes))
	for _, current := range processes {
		tracker.previous[current.Identity] = current.TotalCPUNanos()
	}
	tracker.previousAt = now
	return result
}
