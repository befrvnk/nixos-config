package detector

import (
	"path/filepath"
	"strings"
	"time"

	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
)

type Process struct {
	proc.Process
	Kind       string  `json:"kind"`
	CPUPercent float64 `json:"cpu_percent"`
}

type Activity struct {
	At                time.Time `json:"at"`
	Busy              bool      `json:"busy"`
	Immediate         bool      `json:"immediate"`
	GradleCPUPercent  float64   `json:"gradle_cpu_percent"`
	FalconCPUPercent  float64   `json:"falcon_cpu_percent"`
	RelevantProcesses []Process `json:"processes,omitempty"`
}

type Config struct {
	CPUThreshold   float64
	TriggerSamples int
	Inactivity     time.Duration
	MaximumSession time.Duration
}

type Transition int

const (
	NoTransition Transition = iota
	Started
	StoppedInactive
	StoppedMaximumDuration
)

type Detector struct {
	config         Config
	active         bool
	activeSince    time.Time
	inactiveSince  time.Time
	candidateCount int
	suppressed     bool
}

func New(config Config) *Detector {
	return &Detector{config: config}
}

func (detector *Detector) Observe(now time.Time, activity Activity) Transition {
	if !activity.At.IsZero() {
		now = activity.At
	}
	if !detector.active {
		if detector.suppressed {
			if activity.Busy {
				return NoTransition
			}
			detector.suppressed = false
		}
		if activity.Immediate {
			detector.start(now)
			return Started
		}
		if activity.Busy {
			detector.candidateCount++
		} else {
			detector.candidateCount = 0
		}
		if detector.candidateCount >= detector.config.TriggerSamples {
			detector.start(now)
			return Started
		}
		return NoTransition
	}

	if now.Sub(detector.activeSince) >= detector.config.MaximumSession {
		detector.stop()
		detector.suppressed = true
		return StoppedMaximumDuration
	}
	if activity.Busy {
		detector.inactiveSince = time.Time{}
		return NoTransition
	}
	if detector.inactiveSince.IsZero() {
		detector.inactiveSince = now
		return NoTransition
	}
	if now.Sub(detector.inactiveSince) >= detector.config.Inactivity {
		detector.stop()
		return StoppedInactive
	}
	return NoTransition
}

func (detector *Detector) Active() bool {
	return detector.active
}

func (detector *Detector) start(now time.Time) {
	detector.active = true
	detector.activeSince = now
	detector.inactiveSince = time.Time{}
	detector.candidateCount = 0
}

func (detector *Detector) stop() {
	detector.active = false
	detector.activeSince = time.Time{}
	detector.inactiveSince = time.Time{}
	detector.candidateCount = 0
}

func Classify(now time.Time, processes []proc.Process, cpu map[proc.Identity]float64, threshold float64) Activity {
	activity := Activity{At: now}
	kinds := make(map[int]string)

	for _, current := range processes {
		kind := directKind(current)
		if kind != "" {
			kinds[current.PID] = kind
		}
	}

	// Include native build tools only when they descend from a Gradle-related process.
	changed := true
	for changed {
		changed = false
		for _, current := range processes {
			if _, exists := kinds[current.PID]; exists {
				continue
			}
			if parentKind, exists := kinds[current.PPID]; exists && parentKind != "falcon" && isBuildTool(current) {
				kinds[current.PID] = "gradle-tool"
				changed = true
			}
		}
	}

	for _, current := range processes {
		kind, relevant := kinds[current.PID]
		if !relevant {
			continue
		}
		usage := cpu[current.Identity]
		activity.RelevantProcesses = append(activity.RelevantProcesses, Process{
			Process:    current,
			Kind:       kind,
			CPUPercent: usage,
		})
		if kind == "falcon" {
			activity.FalconCPUPercent += usage
			continue
		}
		activity.GradleCPUPercent += usage
		if kind == "gradle-client" {
			activity.Immediate = true
		}
	}
	activity.Busy = activity.Immediate || activity.GradleCPUPercent >= threshold
	return activity
}

func directKind(current proc.Process) string {
	name := strings.ToLower(current.Name)
	base := strings.ToLower(filepath.Base(current.Path))
	arguments := strings.ToLower(strings.Join(current.Args, "\x00"))
	combined := name + " " + base + " " + strings.ToLower(current.Path)

	if strings.Contains(combined, "com.crowdstrike.falcon.agent") {
		return "falcon"
	}
	if strings.Contains(arguments, "org.gradle.wrapper.gradlewrappermain") ||
		strings.Contains(arguments, "org.gradle.launcher.gradlemain") {
		return "gradle-client"
	}
	if strings.Contains(arguments, "org.gradle.launcher.daemon.bootstrap.gradledaemon") {
		return "gradle-daemon"
	}
	if strings.Contains(arguments, "org.jetbrains.kotlin.daemon") ||
		strings.Contains(arguments, "kotlinc") ||
		strings.Contains(name, "kotlin-daemon") {
		return "gradle-tool"
	}
	if name == "gradle" || base == "gradle" || name == "gradlew" || base == "gradlew" {
		return "gradle-client"
	}
	if name == "aapt2" || base == "aapt2" {
		return "gradle-tool"
	}
	return ""
}

func isBuildTool(current proc.Process) bool {
	name := strings.ToLower(current.Name)
	base := strings.ToLower(filepath.Base(current.Path))
	for _, candidate := range []string{"aapt2", "clang", "clang++", "cmake", "d8", "java", "kotlinc", "ninja", "r8"} {
		if name == candidate || base == candidate {
			return true
		}
	}
	return false
}
