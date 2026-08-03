package observer

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"time"

	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/collector"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/detector"
	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/retention"
	systemmetrics "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/system"
)

type Config struct {
	OutputDirectory       string
	PollInterval          time.Duration
	PreRoll               time.Duration
	GradleCPUThreshold    float64
	TriggerSamples        int
	Inactivity            time.Duration
	MaximumSession        time.Duration
	FalconSampleThreshold float64
	FalconSampleCount     int
	Collectors            collector.Config
	Retention             retention.Config
}

type Dependencies struct {
	Processes proc.Scanner
	System    func() (systemmetrics.Counters, error)
	Now       func() time.Time
}

type record struct {
	At       time.Time            `json:"at"`
	System   systemmetrics.Sample `json:"system"`
	Activity detector.Activity    `json:"activity"`
}

type metadata struct {
	StartedAt time.Time `json:"started_at"`
	Hostname  string    `json:"hostname"`
	Trigger   string    `json:"trigger"`
	Config    struct {
		PollInterval          string  `json:"poll_interval"`
		GradleCPUThreshold    float64 `json:"gradle_cpu_threshold"`
		TriggerSamples        int     `json:"trigger_samples"`
		Inactivity            string  `json:"inactivity"`
		MaximumSession        string  `json:"maximum_session"`
		FalconSampleThreshold float64 `json:"falcon_sample_threshold"`
		CollectorsEnabled     bool    `json:"collectors_enabled"`
	} `json:"config"`
}

type summary struct {
	StartedAt           time.Time `json:"started_at"`
	EndedAt             time.Time `json:"ended_at"`
	StopReason          string    `json:"stop_reason"`
	MaximumGradleCPU    float64   `json:"maximum_gradle_cpu_percent"`
	MaximumFalconCPU    float64   `json:"maximum_falcon_cpu_percent"`
	FalconSampled       bool      `json:"falcon_sampled"`
	CollectorErrorsSeen bool      `json:"collector_errors_seen"`
}

type activeSession struct {
	dir                 string
	startedAt           time.Time
	observations        *os.File
	encoder             *json.Encoder
	collectors          *collector.Session
	maximumGradleCPU    float64
	maximumFalconCPU    float64
	falconSpikeCount    int
	falconSampled       bool
	collectorErrorsSeen bool
}

func Run(ctx context.Context, config Config, dependencies Dependencies, logger *log.Logger) error {
	if dependencies.Processes == nil || dependencies.System == nil {
		return fmt.Errorf("observer dependencies are incomplete")
	}
	if dependencies.Now == nil {
		dependencies.Now = time.Now
	}
	if err := os.MkdirAll(config.OutputDirectory, 0o700); err != nil {
		return fmt.Errorf("create output directory: %w", err)
	}
	if err := os.Chmod(config.OutputDirectory, 0o700); err != nil {
		return fmt.Errorf("secure output directory: %w", err)
	}
	if err := retention.Apply(config.OutputDirectory, "", dependencies.Now(), config.Retention); err != nil {
		logger.Printf("retention warning: %v", err)
	}

	activityDetector := detector.New(detector.Config{
		CPUThreshold:   config.GradleCPUThreshold,
		TriggerSamples: config.TriggerSamples,
		Inactivity:     config.Inactivity,
		MaximumSession: config.MaximumSession,
	})
	cpuTracker := proc.NewCPUTracker()
	systemTracker := &systemmetrics.Tracker{}
	preRollCapacity := int(config.PreRoll/config.PollInterval) + 1
	if preRollCapacity < 1 {
		preRollCapacity = 1
	}
	preRoll := make([]record, 0, preRollCapacity)
	var session *activeSession

	ticker := time.NewTicker(config.PollInterval)
	defer ticker.Stop()
	logger.Printf("observer started: poll=%s collectors=%t output=%s", config.PollInterval, config.Collectors.Enabled, config.OutputDirectory)

	observe := func() {
		now := dependencies.Now()
		processes, err := dependencies.Processes.Scan()
		if err != nil {
			logger.Printf("process scan warning: %v", err)
			return
		}
		cpu := cpuTracker.Calculate(now, processes)
		activity := detector.Classify(now, processes, cpu, config.GradleCPUThreshold)
		counters, err := dependencies.System()
		if err != nil {
			logger.Printf("system metrics warning: %v", err)
			counters.At = now
		}
		systemSample := systemTracker.Calculate(counters)
		current := record{At: now, System: systemSample, Activity: activity}
		preRoll = appendRing(preRoll, current, preRollCapacity)

		transition := activityDetector.Observe(now, activity)
		switch transition {
		case detector.Started:
			trigger := "sustained Gradle CPU"
			if activity.Immediate {
				trigger = "Gradle client process"
			}
			contextRecords := preRoll
			if len(contextRecords) > 0 {
				contextRecords = contextRecords[:len(contextRecords)-1]
			}
			started, startErr := startSession(config, now, trigger, contextRecords, logger)
			if startErr != nil {
				logger.Printf("start session failed: %v", startErr)
				return
			}
			session = started
			logger.Printf("session started: %s (%s)", session.dir, trigger)
		case detector.StoppedInactive, detector.StoppedMaximumDuration:
			if session == nil {
				return
			}
			if err := session.encoder.Encode(current); err != nil {
				logger.Printf("write observation warning: %v", err)
			}
			updateSession(session, activity, config, logger)
			reason := "Gradle inactive"
			if transition == detector.StoppedMaximumDuration {
				reason = "maximum session duration"
			}
			if err := stopSession(session, now, reason, logger); err != nil {
				logger.Printf("stop session warning: %v", err)
			}
			logger.Printf("session stopped: %s (%s)", session.dir, reason)
			session = nil
			if err := retention.Apply(config.OutputDirectory, "", now, config.Retention); err != nil {
				logger.Printf("retention warning: %v", err)
			}
		}

		if session != nil {
			if err := session.encoder.Encode(current); err != nil {
				logger.Printf("write observation warning: %v", err)
			}
			updateSession(session, activity, config, logger)
		}
	}

	observe()
	for {
		select {
		case <-ctx.Done():
			if session != nil {
				if err := stopSession(session, dependencies.Now(), "observer shutdown", logger); err != nil {
					logger.Printf("shutdown session warning: %v", err)
				}
			}
			logger.Printf("observer stopped")
			return nil
		case <-ticker.C:
			observe()
		}
	}
}

func startSession(config Config, now time.Time, trigger string, preRoll []record, logger *log.Logger) (*activeSession, error) {
	dir := filepath.Join(config.OutputDirectory, "session-"+now.UTC().Format("20060102T150405.000000000Z"))
	if err := os.Mkdir(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create session directory: %w", err)
	}
	observations, err := os.OpenFile(filepath.Join(dir, "observations.jsonl"), os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0o600)
	if err != nil {
		return nil, fmt.Errorf("create observation log: %w", err)
	}
	result := &activeSession{
		dir:          dir,
		startedAt:    now,
		observations: observations,
		encoder:      json.NewEncoder(observations),
	}
	for _, previous := range preRoll {
		if err := result.encoder.Encode(previous); err != nil {
			observations.Close()
			return nil, fmt.Errorf("write pre-roll: %w", err)
		}
	}
	if err := writeMetadata(dir, config, now, trigger); err != nil {
		observations.Close()
		return nil, err
	}

	collectors, collectorErr := collector.Start(config.Collectors, dir)
	result.collectors = collectors
	if collectorErr != nil {
		result.collectorErrorsSeen = true
		appendError(dir, collectorErr)
		logger.Printf("collector start warning: %v", collectorErr)
	}
	return result, nil
}

func updateSession(session *activeSession, activity detector.Activity, config Config, logger *log.Logger) {
	if activity.GradleCPUPercent > session.maximumGradleCPU {
		session.maximumGradleCPU = activity.GradleCPUPercent
	}
	if activity.FalconCPUPercent > session.maximumFalconCPU {
		session.maximumFalconCPU = activity.FalconCPUPercent
	}
	if activity.FalconCPUPercent >= config.FalconSampleThreshold {
		session.falconSpikeCount++
	} else {
		session.falconSpikeCount = 0
	}
	if config.Collectors.Enabled && !session.falconSampled && session.falconSpikeCount >= config.FalconSampleCount {
		if pid := falconPID(activity); pid > 0 {
			if err := session.collectors.MaybeSampleFalcon(pid); err != nil {
				session.collectorErrorsSeen = true
				appendError(session.dir, err)
				logger.Printf("Falcon sample warning: %v", err)
			} else {
				session.falconSampled = true
				logger.Printf("Falcon stack sample started for pid %d", pid)
			}
		}
	}
	for _, err := range session.collectors.EnforceFileLimits() {
		session.collectorErrorsSeen = true
		appendError(session.dir, err)
		logger.Printf("collector limit warning: %v", err)
	}
}

func stopSession(session *activeSession, now time.Time, reason string, logger *log.Logger) error {
	var failures []error
	if session.collectors != nil {
		if err := session.collectors.Stop(); err != nil {
			session.collectorErrorsSeen = true
			appendError(session.dir, err)
			failures = append(failures, err)
		}
	}
	if err := session.observations.Close(); err != nil {
		failures = append(failures, err)
	}
	result := summary{
		StartedAt:           session.startedAt,
		EndedAt:             now,
		StopReason:          reason,
		MaximumGradleCPU:    session.maximumGradleCPU,
		MaximumFalconCPU:    session.maximumFalconCPU,
		FalconSampled:       session.falconSampled,
		CollectorErrorsSeen: session.collectorErrorsSeen,
	}
	if err := writeJSON(filepath.Join(session.dir, "summary.json"), result); err != nil {
		failures = append(failures, err)
	}
	return errors.Join(failures...)
}

func writeMetadata(dir string, config Config, now time.Time, trigger string) error {
	hostname, _ := os.Hostname()
	value := metadata{StartedAt: now, Hostname: hostname, Trigger: trigger}
	value.Config.PollInterval = config.PollInterval.String()
	value.Config.GradleCPUThreshold = config.GradleCPUThreshold
	value.Config.TriggerSamples = config.TriggerSamples
	value.Config.Inactivity = config.Inactivity.String()
	value.Config.MaximumSession = config.MaximumSession.String()
	value.Config.FalconSampleThreshold = config.FalconSampleThreshold
	value.Config.CollectorsEnabled = config.Collectors.Enabled
	return writeJSON(filepath.Join(dir, "metadata.json"), value)
}

func writeJSON(path string, value any) error {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0o600)
	if err != nil {
		return err
	}
	encoder := json.NewEncoder(file)
	encoder.SetIndent("", "  ")
	encodeErr := encoder.Encode(value)
	closeErr := file.Close()
	return errors.Join(encodeErr, closeErr)
}

func appendError(dir string, err error) {
	file, openErr := os.OpenFile(filepath.Join(dir, "errors.log"), os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o600)
	if openErr != nil {
		return
	}
	defer file.Close()
	fmt.Fprintf(file, "%s %v\n", time.Now().UTC().Format(time.RFC3339Nano), err)
}

func appendRing(records []record, value record, capacity int) []record {
	if len(records) < capacity {
		return append(records, value)
	}
	copy(records, records[1:])
	records[len(records)-1] = value
	return records
}

func falconPID(activity detector.Activity) int {
	for _, current := range activity.RelevantProcesses {
		if current.Kind == "falcon" {
			return current.PID
		}
	}
	return 0
}
