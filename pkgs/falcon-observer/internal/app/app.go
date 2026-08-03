package app

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"runtime"
	"syscall"
	"time"

	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/collector"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/detector"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/observer"
	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/retention"
	systemmetrics "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/system"
)

var Version = "development"

const usage = `Usage:
  falcon-observer run [options]
  falcon-observer scan [--interval duration]
  falcon-observer version

The run command detects real Gradle activity without changing projects or build
commands. Detailed Falcon collectors start only for bounded Gradle sessions.
Raw output can contain sensitive file paths and must remain local.
`

func Run(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	if runtime.GOOS != "darwin" {
		fmt.Fprintln(stderr, "error: falcon-observer only supports macOS")
		return 1
	}
	if len(args) == 0 {
		fmt.Fprint(stderr, usage)
		return 2
	}
	switch args[0] {
	case "run":
		return runObserver(ctx, args[1:], stdout, stderr)
	case "scan":
		return scan(args[1:], stdout, stderr)
	case "version", "--version":
		fmt.Fprintln(stdout, Version)
		return 0
	case "help", "--help", "-h":
		fmt.Fprint(stdout, usage)
		return 0
	default:
		fmt.Fprint(stderr, usage)
		fmt.Fprintf(stderr, "error: unknown command %q\n", args[0])
		return 2
	}
}

func runObserver(ctx context.Context, args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("run", flag.ContinueOnError)
	flags.SetOutput(stderr)
	outputDirectory := flags.String("output-dir", "/var/log/falcon-observer", "root-owned session output directory")
	pollInterval := flags.Duration("poll-interval", 2*time.Second, "process polling interval")
	preRoll := flags.Duration("pre-roll", 5*time.Minute, "lightweight context retained before a trigger")
	cpuThreshold := flags.Float64("gradle-cpu-threshold", 15, "aggregate Gradle CPU percent needed to indicate activity")
	triggerSamples := flags.Int("trigger-samples", 3, "consecutive active samples before starting a CPU-triggered session")
	inactivity := flags.Duration("inactivity", 90*time.Second, "quiet period before stopping a session")
	maximumSession := flags.Duration("max-session", 45*time.Minute, "maximum detailed collection duration")
	falconSampleThreshold := flags.Float64("falcon-sample-threshold", 50, "Falcon CPU percent needed for an automatic stack sample")
	falconSampleCount := flags.Int("falcon-sample-count", 3, "consecutive Falcon spike samples before stack sampling")
	collectorsEnabled := flags.Bool("collectors", true, "run privileged detailed collectors")
	powermetricsInterval := flags.Duration("powermetrics-interval", 2*time.Second, "powermetrics sampling interval")
	maximumCollectorBytes := flags.Int64("max-collector-bytes", 512*1024*1024, "maximum bytes per collector output")
	retentionAge := flags.Duration("retention-age", 14*24*time.Hour, "raw session retention")
	retentionBytes := flags.Int64("retention-bytes", 5*1024*1024*1024, "maximum total session bytes")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() != 0 {
		fmt.Fprintf(stderr, "error: unexpected arguments: %v\n", flags.Args())
		return 2
	}
	if err := validateDurations(*pollInterval, *maximumSession, *inactivity, *triggerSamples, *falconSampleCount); err != nil {
		fmt.Fprintf(stderr, "error: %v\n", err)
		return 2
	}
	if *collectorsEnabled && os.Geteuid() != 0 {
		fmt.Fprintln(stderr, "error: detailed collectors require root; use sudo or --collectors=false")
		return 1
	}

	syscall.Umask(0o077)
	config := observer.Config{
		OutputDirectory:       *outputDirectory,
		PollInterval:          *pollInterval,
		PreRoll:               *preRoll,
		GradleCPUThreshold:    *cpuThreshold,
		TriggerSamples:        *triggerSamples,
		Inactivity:            *inactivity,
		MaximumSession:        *maximumSession,
		FalconSampleThreshold: *falconSampleThreshold,
		FalconSampleCount:     *falconSampleCount,
		Collectors: collector.Config{
			Enabled:              *collectorsEnabled,
			FalconctlPath:        "/Applications/Falcon.app/Contents/Resources/falconctl",
			FSUsagePath:          "/usr/bin/fs_usage",
			PowermetricsPath:     "/usr/bin/powermetrics",
			SamplePath:           "/usr/bin/sample",
			MaximumDuration:      *maximumSession,
			PowermetricsInterval: *powermetricsInterval,
			MaximumFileBytes:     *maximumCollectorBytes,
		},
		Retention: retention.Config{
			MaximumAge:        *retentionAge,
			MaximumTotalBytes: *retentionBytes,
		},
	}
	logger := log.New(stdout, "falcon-observer: ", log.Ldate|log.Ltime|log.LUTC)
	err := observer.Run(ctx, config, observer.Dependencies{
		Processes: proc.DarwinScanner{},
		System:    systemmetrics.Snapshot,
		Now:       time.Now,
	}, logger)
	if err != nil {
		fmt.Fprintf(stderr, "error: %v\n", err)
		return 1
	}
	return 0
}

func scan(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("scan", flag.ContinueOnError)
	flags.SetOutput(stderr)
	interval := flags.Duration("interval", 2*time.Second, "interval used to calculate CPU utilization")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *interval <= 0 {
		fmt.Fprintln(stderr, "error: interval must be positive")
		return 2
	}
	scanner := proc.DarwinScanner{}
	tracker := proc.NewCPUTracker()
	first, err := scanner.Scan()
	if err != nil {
		fmt.Fprintf(stderr, "error: %v\n", err)
		return 1
	}
	tracker.Calculate(time.Now(), first)
	time.Sleep(*interval)
	second, err := scanner.Scan()
	if err != nil {
		fmt.Fprintf(stderr, "error: %v\n", err)
		return 1
	}
	now := time.Now()
	activity := detector.Classify(now, second, tracker.Calculate(now, second), 15)
	encoder := json.NewEncoder(stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(activity); err != nil {
		fmt.Fprintf(stderr, "error: %v\n", err)
		return 1
	}
	return 0
}

func validateDurations(poll, maximum, inactivity time.Duration, triggerSamples, falconSamples int) error {
	if poll < 250*time.Millisecond {
		return fmt.Errorf("poll interval must be at least 250ms")
	}
	if maximum <= 0 || inactivity <= 0 {
		return fmt.Errorf("session durations must be positive")
	}
	if triggerSamples < 1 || falconSamples < 1 {
		return fmt.Errorf("sample counts must be positive")
	}
	return nil
}
