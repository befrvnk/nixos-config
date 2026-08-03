package observer

import (
	"bytes"
	"context"
	"io"
	"log"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/collector"
	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/retention"
	systemmetrics "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/system"
)

type sequenceScanner struct {
	index int
	items [][]proc.Process
}

func (scanner *sequenceScanner) Scan() ([]proc.Process, error) {
	index := scanner.index
	if index >= len(scanner.items) {
		index = len(scanner.items) - 1
	}
	scanner.index++
	return scanner.items[index], nil
}

func TestRunCreatesAutomaticSessionWithoutPersistingArguments(t *testing.T) {
	root := t.TempDir()
	gradle := proc.Process{
		Identity: proc.Identity{PID: 42, StartTime: 1},
		Name:     "java",
		Path:     "/usr/bin/java",
		Args:     []string{"java", "org.gradle.wrapper.GradleWrapperMain", "secret-project-name"},
	}
	scanner := &sequenceScanner{items: [][]proc.Process{{gradle}, {}, {}, {}}}
	base := time.Unix(1000, 0)
	step := 0
	now := func() time.Time {
		step++
		return base.Add(time.Duration(step) * 20 * time.Millisecond)
	}
	var cpuTicks uint64
	systemSnapshot := func() (systemmetrics.Counters, error) {
		cpuTicks += 100
		return systemmetrics.Counters{
			At:             now(),
			CPUUserTicks:   cpuTicks,
			CPUSystemTicks: cpuTicks,
			CPUIdleTicks:   cpuTicks,
		}, nil
	}
	ctx, cancel := context.WithTimeout(context.Background(), 100*time.Millisecond)
	defer cancel()
	config := Config{
		OutputDirectory:       root,
		PollInterval:          5 * time.Millisecond,
		PreRoll:               time.Minute,
		GradleCPUThreshold:    15,
		TriggerSamples:        1,
		Inactivity:            30 * time.Millisecond,
		MaximumSession:        time.Minute,
		FalconSampleThreshold: 50,
		FalconSampleCount:     3,
		Collectors:            collector.Config{Enabled: false},
		Retention:             retention.Config{MaximumAge: time.Hour, MaximumTotalBytes: 1024 * 1024},
	}
	if err := Run(ctx, config, Dependencies{Processes: scanner, System: systemSnapshot, Now: now}, log.New(io.Discard, "", 0)); err != nil {
		t.Fatal(err)
	}

	sessions, err := filepath.Glob(filepath.Join(root, "session-*"))
	if err != nil || len(sessions) != 1 {
		t.Fatalf("sessions = %v, err = %v", sessions, err)
	}
	if _, err := os.Stat(filepath.Join(sessions[0], "summary.json")); err != nil {
		t.Fatalf("summary missing: %v", err)
	}
	observations, err := os.ReadFile(filepath.Join(sessions[0], "observations.jsonl"))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(observations, []byte("secret-project-name")) {
		t.Fatal("process arguments leaked into observation log")
	}
	metadata, err := os.ReadFile(filepath.Join(sessions[0], "metadata.json"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(metadata), "Gradle client process") {
		t.Fatalf("unexpected metadata: %s", metadata)
	}
}
