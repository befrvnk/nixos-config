package observer

import (
	"testing"
	"time"

	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/detector"
	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
	systemmetrics "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/system"
)

func TestAccumulatorBuildsResourceSummary(t *testing.T) {
	start := time.Unix(1000, 0)
	identity := proc.Identity{PID: 10, StartTime: 1}
	makeRecord := func(at time.Time, cpu float64, totalNanos, read uint64) record {
		return record{
			At:     at,
			System: systemmetrics.Sample{CPUIdlePercent: 20, CompressedBytes: 100, SwapUsedBytes: 50},
			Activity: detector.Activity{
				FalconCPUPercent: cpu,
				BuildCPUPercent:  200,
				RelevantProcesses: []detector.Process{{
					Process: proc.Process{Identity: identity, UserNanos: totalNanos, ReadBytes: read},
					Kind:    "falcon",
				}},
			},
		}
	}
	var values accumulator
	values.add(makeRecord(start, 100, 1_000_000_000, 1024))
	values.add(makeRecord(start.Add(time.Second), 200, 3_000_000_000, 4096))
	summary := values.summary()
	if summary.FalconCPUPercent.Mean != 150 || summary.FalconDelta.CPUSeconds != 2 || summary.FalconDelta.ReadBytes != 3072 {
		t.Fatalf("summary = %#v", summary)
	}
	if summary.SystemCPUPercent.Mean != 80 {
		t.Fatalf("system CPU = %#v", summary.SystemCPUPercent)
	}
}
