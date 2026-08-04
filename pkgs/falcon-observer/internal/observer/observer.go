package observer

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/collector"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/deeptrace"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/detector"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/falconstats"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/powermetrics"
	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/retention"
	systemmetrics "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/system"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/trace"
)

type Config struct {
	OutputDirectory       string
	ProjectRoot           string
	PollInterval          time.Duration
	PreRoll               time.Duration
	BuildCPUThreshold     float64
	TriggerSamples        int
	Inactivity            time.Duration
	MaximumSession        time.Duration
	FalconSampleThreshold float64
	FalconSampleCount     int
	DeepTraceMode         string
	DeepTraceInterval     time.Duration
	RetainRawData         bool
	RetentionInterval     time.Duration
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
	StartedAt   time.Time `json:"started_at"`
	Hostname    string    `json:"hostname"`
	Trigger     string    `json:"trigger"`
	Project     string    `json:"project,omitempty"`
	BuildSystem string    `json:"build_system,omitempty"`
	DeepTrace   bool      `json:"deep_trace"`
	Config      struct {
		PollInterval          string  `json:"poll_interval"`
		BuildCPUThreshold     float64 `json:"build_cpu_threshold"`
		TriggerSamples        int     `json:"trigger_samples"`
		Inactivity            string  `json:"inactivity"`
		MaximumSession        string  `json:"maximum_session"`
		FalconSampleThreshold float64 `json:"falcon_sample_threshold"`
		CollectorsEnabled     bool    `json:"collectors_enabled"`
		DeepTraceMode         string  `json:"deep_trace_mode"`
	} `json:"config"`
}

type metricSummary struct {
	Samples int     `json:"samples"`
	Mean    float64 `json:"mean"`
	P50     float64 `json:"p50"`
	P95     float64 `json:"p95"`
	P99     float64 `json:"p99"`
	Maximum float64 `json:"maximum"`
}

type resourceDelta struct {
	CPUSeconds   float64 `json:"cpu_seconds"`
	ReadBytes    uint64  `json:"read_bytes"`
	WrittenBytes uint64  `json:"written_bytes"`
}

type phaseSummary struct {
	DurationSeconds        float64       `json:"duration_seconds"`
	FalconCPUPercent       metricSummary `json:"falcon_cpu_percent"`
	BuildCPUPercent        metricSummary `json:"build_cpu_percent"`
	SystemCPUPercent       metricSummary `json:"system_cpu_percent"`
	MaximumCompressedBytes uint64        `json:"maximum_compressed_bytes"`
	MaximumSwapBytes       uint64        `json:"maximum_swap_bytes"`
	FalconDelta            resourceDelta `json:"falcon_delta"`
}

type summary struct {
	StartedAt            time.Time            `json:"started_at"`
	EndedAt              time.Time            `json:"ended_at"`
	StopReason           string               `json:"stop_reason"`
	Project              string               `json:"project,omitempty"`
	BuildSystem          string               `json:"build_system,omitempty"`
	Baseline             phaseSummary         `json:"baseline"`
	Build                phaseSummary         `json:"build"`
	FalconCPUMultiplier  float64              `json:"falcon_cpu_multiplier,omitempty"`
	FalconReadMultiplier float64              `json:"falcon_read_multiplier,omitempty"`
	Powermetrics         powermetrics.Summary `json:"powermetrics"`
	FalconStats          falconstats.Delta    `json:"falcon_stats_delta"`
	FileActivity         *trace.Summary       `json:"file_activity,omitempty"`
	Collectors           collector.Status     `json:"collectors"`
	RawDataRetained      bool                 `json:"raw_data_retained"`
	CollectorErrorsSeen  bool                 `json:"collector_errors_seen"`
}

type accumulator struct {
	startedAt, endedAt             time.Time
	falconCPU, buildCPU, systemCPU []float64
	maximumCompressed, maximumSwap uint64
	firstFalcon, lastFalcon        *proc.Process
}

type activeSession struct {
	dir                 string
	startedAt           time.Time
	project             string
	buildSystem         string
	deepTrace           bool
	observations        *os.File
	encoder             *json.Encoder
	collectors          *collector.Session
	baseline            accumulator
	build               accumulator
	falconSpikeCount    int
	collectorErrorsSeen bool
	lastRetention       time.Time
}

func Run(ctx context.Context, config Config, dependencies Dependencies, logger *log.Logger) error {
	if dependencies.Processes == nil || dependencies.System == nil {
		return fmt.Errorf("observer dependencies are incomplete")
	}
	if dependencies.Now == nil {
		dependencies.Now = time.Now
	}
	if config.RetentionInterval <= 0 {
		config.RetentionInterval = time.Minute
	}
	if err := deeptrace.ValidateMode(config.DeepTraceMode); err != nil {
		return err
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
		CPUThreshold:   config.BuildCPUThreshold,
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
	logger.Printf("observer started: poll=%s collectors=%t deep=%s output=%s", config.PollInterval, config.Collectors.Enabled, config.DeepTraceMode, config.OutputDirectory)

	observe := func() {
		now := dependencies.Now()
		processes, err := dependencies.Processes.Scan()
		if err != nil {
			logger.Printf("process scan warning: %v", err)
			return
		}
		cpu := cpuTracker.Calculate(now, processes)
		activity := detector.ClassifyUnderRoot(now, processes, cpu, config.BuildCPUThreshold, config.ProjectRoot)
		counters, err := dependencies.System()
		if err != nil {
			logger.Printf("system metrics warning: %v", err)
			counters.At = now
		}
		current := record{At: now, System: systemTracker.Calculate(counters), Activity: activity}
		preRoll = appendRing(preRoll, current, preRollCapacity)

		transition := activityDetector.Observe(now, activity)
		switch transition {
		case detector.Started:
			trigger := "sustained build CPU"
			if activity.Immediate {
				trigger = "build client process"
			}
			contextRecords := preRoll
			if len(contextRecords) > 0 {
				contextRecords = contextRecords[:len(contextRecords)-1]
			}
			started, startErr := startSession(config, now, trigger, activity, contextRecords, logger)
			if startErr != nil {
				logger.Printf("start session failed: %v", startErr)
				return
			}
			session = started
			logger.Printf("session started: %s (project=%s system=%s deep=%t)", session.dir, fallback(session.project, "unknown"), fallback(session.buildSystem, "unknown"), session.deepTrace)
		case detector.StoppedInactive, detector.StoppedMaximumDuration:
			if session == nil {
				return
			}
			recordSession(session, current, config, logger)
			reason := "build inactive"
			if transition == detector.StoppedMaximumDuration {
				reason = "maximum session duration"
			}
			if err := stopSession(session, now, reason, config, logger); err != nil {
				logger.Printf("stop session warning: %v", err)
			}
			logger.Printf("session stopped: %s (%s)", session.dir, reason)
			session = nil
			if err := retention.Apply(config.OutputDirectory, "", now, config.Retention); err != nil {
				logger.Printf("retention warning: %v", err)
			}
		}

		if session != nil {
			recordSession(session, current, config, logger)
			if now.Sub(session.lastRetention) >= config.RetentionInterval {
				if err := retention.Apply(config.OutputDirectory, session.dir, now, config.Retention); err != nil {
					logger.Printf("retention warning: %v", err)
				}
				session.lastRetention = now
			}
		}
	}

	observe()
	for {
		select {
		case <-ctx.Done():
			if session != nil {
				if err := stopSession(session, dependencies.Now(), "observer shutdown", config, logger); err != nil {
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

func startSession(config Config, now time.Time, trigger string, activity detector.Activity, preRoll []record, logger *log.Logger) (*activeSession, error) {
	deep := false
	if config.Collectors.Enabled {
		var err error
		deep, err = deeptrace.ShouldRun(config.OutputDirectory, activity.Project, activity.BuildSystem, config.DeepTraceMode, config.DeepTraceInterval, now)
		if err != nil {
			logger.Printf("deep trace policy warning: %v", err)
			deep = false
		}
	}
	if deep {
		if err := retention.Reserve(config.OutputDirectory, now, config.Retention, config.Collectors.FSUsageMaximumFileBytes); err != nil {
			logger.Printf("deep trace retention reservation warning: %v", err)
			_ = deeptrace.Request(config.OutputDirectory, activity.Project, activity.BuildSystem)
			deep = false
		}
	}
	dir := filepath.Join(config.OutputDirectory, "session-"+now.UTC().Format("20060102T150405.000000000Z"))
	if err := os.Mkdir(dir, 0o700); err != nil {
		return nil, fmt.Errorf("create session directory: %w", err)
	}
	observations, err := os.OpenFile(filepath.Join(dir, "observations.jsonl"), os.O_CREATE|os.O_WRONLY|os.O_EXCL, 0o600)
	if err != nil {
		return nil, fmt.Errorf("create observation log: %w", err)
	}
	result := &activeSession{
		dir: dir, startedAt: now, project: activity.Project, buildSystem: activity.BuildSystem,
		deepTrace: deep, observations: observations, encoder: json.NewEncoder(observations), lastRetention: now,
	}
	for _, previous := range preRoll {
		result.baseline.add(previous)
		if err := result.encoder.Encode(previous); err != nil {
			observations.Close()
			return nil, fmt.Errorf("write pre-roll: %w", err)
		}
	}
	if err := writeMetadata(dir, config, now, trigger, activity.Project, activity.BuildSystem, deep); err != nil {
		observations.Close()
		return nil, err
	}

	collectors, collectorErr := collector.Start(config.Collectors, dir, deep)
	result.collectors = collectors
	if collectorErr != nil {
		result.collectorErrorsSeen = true
		appendError(dir, collectorErr)
		logger.Printf("collector start warning: %v", collectorErr)
	}
	return result, nil
}

func recordSession(session *activeSession, current record, config Config, logger *log.Logger) {
	if current.Activity.Busy {
		if current.Activity.Project != "" {
			session.project = current.Activity.Project
		}
		if current.Activity.BuildSystem != "" {
			session.buildSystem = current.Activity.BuildSystem
		}
	}
	if err := session.encoder.Encode(current); err != nil {
		logger.Printf("write observation warning: %v", err)
	}
	session.build.add(current)
	if current.Activity.FalconCPUPercent >= config.FalconSampleThreshold {
		session.falconSpikeCount++
	} else {
		session.falconSpikeCount = 0
	}
	status := session.collectors.Status()
	if config.Collectors.Enabled && !status.FalconSampled && session.falconSpikeCount >= config.FalconSampleCount {
		if pid := falconPID(current.Activity); pid > 0 {
			if err := session.collectors.MaybeSampleFalcon(pid); err != nil {
				session.collectorErrorsSeen = true
				appendError(session.dir, err)
				logger.Printf("Falcon sample warning: %v", err)
			} else {
				logger.Printf("Falcon stack sample started for pid %d", pid)
			}
		}
	}
	for _, notice := range session.collectors.EnforceFileLimits() {
		if notice.Err != nil {
			session.collectorErrorsSeen = true
			appendError(session.dir, notice.Err)
			logger.Printf("collector limit warning: %v", notice.Err)
		} else if notice.Message != "" {
			logger.Printf("collector notice: %s", notice.Message)
		}
	}
}

func stopSession(session *activeSession, now time.Time, reason string, config Config, logger *log.Logger) error {
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
		StartedAt: nowOr(session.startedAt, session.build.startedAt), EndedAt: now, StopReason: reason,
		Project: session.project, BuildSystem: session.buildSystem,
		Baseline: session.baseline.summary(), Build: session.build.summary(),
		Collectors:          session.collectors.Status(),
		CollectorErrorsSeen: session.collectorErrorsSeen,
	}
	summaryComplete := true
	if result.Baseline.FalconCPUPercent.Mean > 0 {
		result.FalconCPUMultiplier = result.Build.FalconCPUPercent.Mean / result.Baseline.FalconCPUPercent.Mean
	}
	baselineReadRate := readRate(result.Baseline)
	if baselineReadRate > 0 {
		result.FalconReadMultiplier = readRate(result.Build) / baselineReadRate
	}
	if parsed, err := powermetrics.ParseFile(filepath.Join(session.dir, "powermetrics.txt")); err == nil {
		result.Powermetrics = parsed
	} else if config.Collectors.Enabled {
		appendError(session.dir, fmt.Errorf("summarize powermetrics: %w", err))
		result.CollectorErrorsSeen = true
		summaryComplete = false
	}
	if delta, err := falconstats.DiffFiles(filepath.Join(session.dir, "falcon-stats-start.plist"), filepath.Join(session.dir, "falcon-stats-end.plist")); err == nil {
		result.FalconStats = delta
	} else if config.Collectors.Enabled {
		appendError(session.dir, fmt.Errorf("summarize Falcon stats: %w", err))
		result.CollectorErrorsSeen = true
		summaryComplete = false
	}
	if path := session.collectors.FSUsagePath(); path != "" {
		if parsed, err := trace.ParseFile(path, session.project); err == nil {
			result.FileActivity = &parsed
		} else {
			appendError(session.dir, fmt.Errorf("summarize fs_usage: %w", err))
			result.CollectorErrorsSeen = true
			summaryComplete = false
		}
	}
	result.RawDataRetained = config.RetainRawData || !summaryComplete
	if err := writeJSON(filepath.Join(session.dir, "summary.json"), result); err != nil {
		failures = append(failures, err)
	}
	if err := writeMarkdown(filepath.Join(session.dir, "summary.md"), result); err != nil {
		failures = append(failures, err)
	}
	if !result.RawDataRetained {
		for _, name := range []string{
			"observations.jsonl", "falcon-fs-usage.log", "powermetrics.txt", "powermetrics-command.log",
			"falcon-stats-start.plist", "falcon-stats-end.plist", "falcon-sample-command.log",
		} {
			if err := os.Remove(filepath.Join(session.dir, name)); err != nil && !os.IsNotExist(err) {
				logger.Printf("raw data cleanup warning: %v", err)
			}
		}
	}
	return errors.Join(failures...)
}

func (accumulator *accumulator) add(current record) {
	if accumulator.startedAt.IsZero() {
		accumulator.startedAt = current.At
	}
	accumulator.endedAt = current.At
	accumulator.falconCPU = append(accumulator.falconCPU, current.Activity.FalconCPUPercent)
	accumulator.buildCPU = append(accumulator.buildCPU, current.Activity.BuildCPUPercent)
	if current.System.CPUIdlePercent > 0 || current.System.CPUUserPercent > 0 || current.System.CPUSystemPercent > 0 {
		accumulator.systemCPU = append(accumulator.systemCPU, 100-current.System.CPUIdlePercent)
	}
	accumulator.maximumCompressed = max(accumulator.maximumCompressed, current.System.CompressedBytes)
	accumulator.maximumSwap = max(accumulator.maximumSwap, current.System.SwapUsedBytes)
	if falcon := falconProcess(current.Activity); falcon != nil {
		copy := falcon.Process
		if accumulator.firstFalcon == nil {
			accumulator.firstFalcon = &copy
		}
		accumulator.lastFalcon = &copy
	}
}

func (accumulator accumulator) summary() phaseSummary {
	result := phaseSummary{
		FalconCPUPercent:       summarizeMetric(accumulator.falconCPU),
		BuildCPUPercent:        summarizeMetric(accumulator.buildCPU),
		SystemCPUPercent:       summarizeMetric(accumulator.systemCPU),
		MaximumCompressedBytes: accumulator.maximumCompressed,
		MaximumSwapBytes:       accumulator.maximumSwap,
	}
	if !accumulator.startedAt.IsZero() && !accumulator.endedAt.IsZero() {
		result.DurationSeconds = accumulator.endedAt.Sub(accumulator.startedAt).Seconds()
	}
	if accumulator.firstFalcon != nil && accumulator.lastFalcon != nil {
		first, last := accumulator.firstFalcon, accumulator.lastFalcon
		result.FalconDelta.CPUSeconds = float64(nonNegative(last.TotalCPUNanos(), first.TotalCPUNanos())) / 1e9
		result.FalconDelta.ReadBytes = nonNegative(last.ReadBytes, first.ReadBytes)
		result.FalconDelta.WrittenBytes = nonNegative(last.WrittenBytes, first.WrittenBytes)
	}
	return result
}

func summarizeMetric(values []float64) metricSummary {
	if len(values) == 0 {
		return metricSummary{}
	}
	copy := append([]float64(nil), values...)
	sort.Float64s(copy)
	var total float64
	for _, value := range copy {
		total += value
	}
	return metricSummary{
		Samples: len(copy), Mean: total / float64(len(copy)), P50: percentile(copy, .50),
		P95: percentile(copy, .95), P99: percentile(copy, .99), Maximum: copy[len(copy)-1],
	}
}

func percentile(sorted []float64, fraction float64) float64 {
	return sorted[int(fraction*float64(len(sorted)-1))]
}

func readRate(phase phaseSummary) float64 {
	if phase.DurationSeconds <= 0 {
		return 0
	}
	return float64(phase.FalconDelta.ReadBytes) / phase.DurationSeconds
}

func writeMetadata(dir string, config Config, now time.Time, trigger, project, buildSystem string, deep bool) error {
	hostname, _ := os.Hostname()
	value := metadata{StartedAt: now, Hostname: hostname, Trigger: trigger, Project: project, BuildSystem: buildSystem, DeepTrace: deep}
	value.Config.PollInterval = config.PollInterval.String()
	value.Config.BuildCPUThreshold = config.BuildCPUThreshold
	value.Config.TriggerSamples = config.TriggerSamples
	value.Config.Inactivity = config.Inactivity.String()
	value.Config.MaximumSession = config.MaximumSession.String()
	value.Config.FalconSampleThreshold = config.FalconSampleThreshold
	value.Config.CollectorsEnabled = config.Collectors.Enabled
	value.Config.DeepTraceMode = config.DeepTraceMode
	return writeJSON(filepath.Join(dir, "metadata.json"), value)
}

func writeMarkdown(path string, value summary) error {
	var output strings.Builder
	fmt.Fprintln(&output, "# Falcon build-impact summary")
	fmt.Fprintln(&output)
	fmt.Fprintf(&output, "- Project: `%s`\n", fallback(value.Project, "unknown"))
	fmt.Fprintf(&output, "- Build system: `%s`\n", fallback(value.BuildSystem, "unknown"))
	fmt.Fprintf(&output, "- Started: %s\n", value.StartedAt.Format(time.RFC3339))
	fmt.Fprintf(&output, "- Ended: %s\n", value.EndedAt.Format(time.RFC3339))
	fmt.Fprintf(&output, "- Stop reason: %s\n", value.StopReason)
	fmt.Fprintf(&output, "- Deep trace: %t\n", value.Collectors.DeepTrace)
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Falcon impact")
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "| Metric | Baseline | Build |")
	fmt.Fprintln(&output, "| --- | ---: | ---: |")
	fmt.Fprintf(&output, "| Mean CPU (%% of one core) | %.2f | %.2f |\n", value.Baseline.FalconCPUPercent.Mean, value.Build.FalconCPUPercent.Mean)
	fmt.Fprintf(&output, "| p95 CPU | %.2f | %.2f |\n", value.Baseline.FalconCPUPercent.P95, value.Build.FalconCPUPercent.P95)
	fmt.Fprintf(&output, "| Maximum CPU | %.2f | %.2f |\n", value.Baseline.FalconCPUPercent.Maximum, value.Build.FalconCPUPercent.Maximum)
	fmt.Fprintf(&output, "| Physical reads | %.3f GiB | %.3f GiB |\n", gib(value.Baseline.FalconDelta.ReadBytes), gib(value.Build.FalconDelta.ReadBytes))
	fmt.Fprintf(&output, "| CPU time | %.2f s | %.2f s |\n", value.Baseline.FalconDelta.CPUSeconds, value.Build.FalconDelta.CPUSeconds)
	fmt.Fprintln(&output)
	fmt.Fprintf(&output, "Falcon CPU multiplier: **%.2fx**; read-rate multiplier: **%.2fx**.\n", value.FalconCPUMultiplier, value.FalconReadMultiplier)
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Independent powermetrics")
	fmt.Fprintln(&output)
	fmt.Fprintf(&output, "- Falcon mean/p95/max CPU: %.2f%% / %.2f%% / %.2f%%\n", value.Powermetrics.Falcon.MeanCPUPercent, value.Powermetrics.Falcon.P95CPUPercent, value.Powermetrics.Falcon.MaximumCPUPercent)
	fmt.Fprintf(&output, "- Falcon mean/max read rate: %.2f / %.2f MiB/s\n", mib(value.Powermetrics.Falcon.MeanReadBytesPerSec), mib(value.Powermetrics.Falcon.MaximumReadBytesPerSec))
	fmt.Fprintf(&output, "- fs_usage mean/max CPU: %.2f%% / %.2f%%\n", value.Powermetrics.FSUsage.MeanCPUPercent, value.Powermetrics.FSUsage.MaximumCPUPercent)
	fmt.Fprintf(&output, "- powermetrics mean/max CPU: %.2f%% / %.2f%%\n", value.Powermetrics.Powermetrics.MeanCPUPercent, value.Powermetrics.Powermetrics.MaximumCPUPercent)
	fmt.Fprintln(&output)
	fmt.Fprintln(&output, "## Falcon sensor deltas")
	fmt.Fprintln(&output)
	fmt.Fprintf(&output, "- Queue entries processed: %d\n", value.FalconStats.QueueProcessed)
	fmt.Fprintf(&output, "- Sensor-cache read hits/misses: %d / %d\n", value.FalconStats.CacheReadHits, value.FalconStats.CacheReadMisses)
	fmt.Fprintf(&output, "- Endpoint Security exec authorizations: %d\n", value.FalconStats.AuthExec)
	fmt.Fprintf(&output, "- Static-analysis requests/too-large: %d / %d\n", value.FalconStats.StaticRequests, value.FalconStats.StaticTooLarge)
	fmt.Fprintf(&output, "- Rolling one-hour Java class/JAR/ZIP event net: %d / %d / %d\n", value.FalconStats.JavaClassWrittenNet, value.FalconStats.JarWrittenNet, value.FalconStats.ZipWrittenNet)
	if value.FileActivity != nil {
		fmt.Fprintln(&output)
		fmt.Fprintln(&output, "## Bounded file-activity sample")
		fmt.Fprintln(&output)
		fmt.Fprintf(&output, "- Raw bytes processed: %.2f MiB\n", mib(float64(value.FileActivity.RawBytes)))
		fmt.Fprintf(&output, "- Falcon-attributed lines: %d\n", value.FileActivity.FalconLines)
		fmt.Fprintf(&output, "- Path events: %d\n", value.FileActivity.PathEvents)
		fmt.Fprintf(&output, "- Truncated at file limit: %t\n", value.Collectors.FSUsageTruncated)
	}
	fmt.Fprintln(&output)
	fmt.Fprintf(&output, "Collector errors seen: %t. Powermetrics truncated: %t. Raw data retained: %t.\n", value.CollectorErrorsSeen, value.Collectors.PowermetricsTruncated, value.RawDataRetained)
	return os.WriteFile(path, []byte(output.String()), 0o600)
}

func gib(bytes uint64) float64 {
	return float64(bytes) / (1024 * 1024 * 1024)
}

func mib(bytes float64) float64 {
	return bytes / (1024 * 1024)
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

func falconProcess(activity detector.Activity) *detector.Process {
	for index := range activity.RelevantProcesses {
		if activity.RelevantProcesses[index].Kind == "falcon" {
			return &activity.RelevantProcesses[index]
		}
	}
	return nil
}

func falconPID(activity detector.Activity) int {
	if current := falconProcess(activity); current != nil {
		return current.PID
	}
	return 0
}

func nonNegative(current, previous uint64) uint64 {
	if current < previous {
		return 0
	}
	return current - previous
}

func max(left, right uint64) uint64 {
	if right > left {
		return right
	}
	return left
}

func fallback(value, alternative string) string {
	if value == "" {
		return alternative
	}
	return value
}

func nowOr(primary, alternative time.Time) time.Time {
	if !primary.IsZero() {
		return primary
	}
	return alternative
}
