package process

import (
	"math"
	"testing"
	"time"
)

func TestCPUTrackerCalculatesPercentAndHandlesPIDReuse(t *testing.T) {
	tracker := NewCPUTracker()
	start := time.Unix(1000, 0)
	identity := Identity{PID: 10, StartTime: 100}
	tracker.Calculate(start, []Process{{Identity: identity, UserNanos: 1_000_000_000}})

	usage := tracker.Calculate(start.Add(2*time.Second), []Process{{Identity: identity, UserNanos: 2_000_000_000}})
	if math.Abs(usage[identity]-50) > 0.001 {
		t.Fatalf("CPU percent = %f, want 50", usage[identity])
	}

	reused := Identity{PID: 10, StartTime: 200}
	usage = tracker.Calculate(start.Add(4*time.Second), []Process{{Identity: reused, UserNanos: 500_000_000}})
	if _, exists := usage[reused]; exists {
		t.Fatal("PID reuse unexpectedly produced a CPU delta")
	}
}
