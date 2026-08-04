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
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/deeptrace"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/detector"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/observer"
	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
	"github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/retention"
	systemmetrics "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/system"
)

var Version = "development"

const usage = `Usage:
  falcon-observer run [options]
  falcon-observer scan [--interval duration] [--project-root path]
  falcon-observer request-deep-trace --project name --build-system name
  falcon-observer version

The run command detects Gradle, Rust, Go, Node, native, Xcode, and Nix build
activity without changing projects or build commands. Standard sessions use
low-overhead counters and powermetrics. Bounded fs_usage deep traces are
rate-limited per project and summarized without retaining sensitive raw paths by
default.
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
	case "request-deep-trace":
		return requestDeepTrace(args[1:], stdout, stderr)
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
	projectRoot := flags.String("project-root", "/Users/frank/projects", "parent directory used for project attribution")
	pollInterval := flags.Duration("poll-interval", time.Second, "process polling interval")
	preRoll := flags.Duration("pre-roll", 5*time.Minute, "lightweight context retained before a trigger")
	cpuThreshold := flags.Float64("build-cpu-threshold", 25, "aggregate build CPU percent needed to indicate activity")
	triggerSamples := flags.Int("trigger-samples", 1, "consecutive active samples before starting a CPU-triggered session")
	inactivity := flags.Duration("inactivity", 90*time.Second, "quiet period before stopping a session")
	maximumSession := flags.Duration("max-session", 45*time.Minute, "maximum standard collection duration")
	falconSampleThreshold := flags.Float64("falcon-sample-threshold", 150, "Falcon CPU percent needed for an automatic stack sample")
	falconSampleCount := flags.Int("falcon-sample-count", 3, "consecutive Falcon spike samples before stack sampling")
	collectorsEnabled := flags.Bool("collectors", true, "run privileged standard collectors")
	powermetricsInterval := flags.Duration("powermetrics-interval", 2*time.Second, "powermetrics sampling interval")
	maximumCollectorBytes := flags.Int64("max-collector-bytes", 128*1024*1024, "maximum bytes per standard collector output")
	deepTraceMode := flags.String("deep-trace", deeptrace.ModeOff, "fs_usage policy: off, daily, or always; explicit requests override off")
	deepTraceInterval := flags.Duration("deep-trace-interval", 24*time.Hour, "minimum interval between automatic deep traces per project")
	deepTraceDuration := flags.Duration("deep-trace-duration", 60*time.Second, "maximum fs_usage deep trace duration")
	deepTraceBytes := flags.Int64("deep-trace-bytes", 64*1024*1024, "maximum fs_usage deep trace bytes")
	retainRawData := flags.Bool("retain-raw-data", false, "retain observations and raw collector output after summarizing")
	retentionAge := flags.Duration("retention-age", 14*24*time.Hour, "session-summary retention")
	retentionBytes := flags.Int64("retention-bytes", 2*1024*1024*1024, "maximum total session bytes")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if flags.NArg() != 0 {
		fmt.Fprintf(stderr, "error: unexpected arguments: %v\n", flags.Args())
		return 2
	}
	if err := validateConfig(*pollInterval, *maximumSession, *inactivity, *deepTraceDuration, *triggerSamples, *falconSampleCount, *deepTraceMode); err != nil {
		fmt.Fprintf(stderr, "error: %v\n", err)
		return 2
	}
	if *collectorsEnabled && os.Geteuid() != 0 {
		fmt.Fprintln(stderr, "error: standard collectors require root; use sudo or --collectors=false")
		return 1
	}

	syscall.Umask(0o077)
	config := observer.Config{
		OutputDirectory:       *outputDirectory,
		ProjectRoot:           *projectRoot,
		PollInterval:          *pollInterval,
		PreRoll:               *preRoll,
		BuildCPUThreshold:     *cpuThreshold,
		TriggerSamples:        *triggerSamples,
		Inactivity:            *inactivity,
		MaximumSession:        *maximumSession,
		FalconSampleThreshold: *falconSampleThreshold,
		FalconSampleCount:     *falconSampleCount,
		DeepTraceMode:         *deepTraceMode,
		DeepTraceInterval:     *deepTraceInterval,
		RetainRawData:         *retainRawData,
		RetentionInterval:     time.Minute,
		Collectors: collector.Config{
			Enabled:                 *collectorsEnabled,
			FalconctlPath:           "/Applications/Falcon.app/Contents/Resources/falconctl",
			FSUsagePath:             "/usr/bin/fs_usage",
			PowermetricsPath:        "/usr/bin/powermetrics",
			SamplePath:              "/usr/bin/sample",
			MaximumDuration:         *maximumSession,
			PowermetricsInterval:    *powermetricsInterval,
			MaximumFileBytes:        *maximumCollectorBytes,
			FSUsageDuration:         *deepTraceDuration,
			FSUsageMaximumFileBytes: *deepTraceBytes,
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

func requestDeepTrace(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("request-deep-trace", flag.ContinueOnError)
	flags.SetOutput(stderr)
	outputDirectory := flags.String("output-dir", "/var/log/falcon-observer", "observer output directory")
	project := flags.String("project", "", "project/worktree basename")
	buildSystem := flags.String("build-system", "", "build system name")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *project == "" || *buildSystem == "" {
		fmt.Fprintln(stderr, "error: --project and --build-system are required")
		return 2
	}
	if err := deeptrace.Request(*outputDirectory, *project, *buildSystem); err != nil {
		fmt.Fprintf(stderr, "error: request deep trace: %v\n", err)
		return 1
	}
	fmt.Fprintf(stdout, "The next %s build for %s will receive a deep trace.\n", *buildSystem, *project)
	return 0
}

func scan(args []string, stdout, stderr io.Writer) int {
	flags := flag.NewFlagSet("scan", flag.ContinueOnError)
	flags.SetOutput(stderr)
	interval := flags.Duration("interval", 2*time.Second, "interval used to calculate CPU utilization")
	projectRoot := flags.String("project-root", "/Users/frank/projects", "parent directory used for project attribution")
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
	activity := detector.ClassifyUnderRoot(now, second, tracker.Calculate(now, second), 25, *projectRoot)
	encoder := json.NewEncoder(stdout)
	encoder.SetIndent("", "  ")
	if err := encoder.Encode(activity); err != nil {
		fmt.Fprintf(stderr, "error: %v\n", err)
		return 1
	}
	return 0
}

func validateConfig(poll, maximum, inactivity, deepDuration time.Duration, triggerSamples, falconSamples int, deepMode string) error {
	if poll < 250*time.Millisecond {
		return fmt.Errorf("poll interval must be at least 250ms")
	}
	if maximum <= 0 || inactivity <= 0 || deepDuration <= 0 {
		return fmt.Errorf("session and deep-trace durations must be positive")
	}
	if triggerSamples < 1 || falconSamples < 1 {
		return fmt.Errorf("sample counts must be positive")
	}
	return deeptrace.ValidateMode(deepMode)
}
