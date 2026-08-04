package detector

import (
	"path/filepath"
	"strings"
	"time"

	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
)

type Process struct {
	proc.Process
	Kind        string  `json:"kind"`
	BuildSystem string  `json:"build_system,omitempty"`
	Project     string  `json:"project,omitempty"`
	CPUPercent  float64 `json:"cpu_percent"`
}

type Activity struct {
	At                time.Time `json:"at"`
	Busy              bool      `json:"busy"`
	Immediate         bool      `json:"immediate"`
	Project           string    `json:"project,omitempty"`
	BuildSystem       string    `json:"build_system,omitempty"`
	BuildCPUPercent   float64   `json:"build_cpu_percent"`
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

type classification struct {
	kind      string
	system    string
	project   string
	immediate bool
}

func Classify(now time.Time, processes []proc.Process, cpu map[proc.Identity]float64, threshold float64) Activity {
	return ClassifyUnderRoot(now, processes, cpu, threshold, "")
}

func ClassifyUnderRoot(now time.Time, processes []proc.Process, cpu map[proc.Identity]float64, threshold float64, projectRoot string) Activity {
	activity := Activity{At: now}
	classes := make(map[int]classification)

	for _, current := range processes {
		if value, ok := directClassification(current, projectRoot); ok {
			classes[current.PID] = value
		}
	}

	// Attribute compiler and packaging subprocesses to an already recognized
	// build ancestor instead of treating every compiler on the machine as a build.
	changed := true
	for changed {
		changed = false
		for _, current := range processes {
			if _, exists := classes[current.PID]; exists {
				continue
			}
			parent, exists := classes[current.PPID]
			if !exists || parent.kind == "falcon" || !isBuildTool(current) {
				continue
			}
			classes[current.PID] = classification{
				kind:    "build-tool",
				system:  parent.system,
				project: firstNonEmpty(projectForProcess(current, projectRoot), parent.project),
			}
			changed = true
		}
	}

	type projectScore struct {
		project string
		system  string
		score   float64
	}
	scores := make(map[string]projectScore)
	for _, current := range processes {
		class, relevant := classes[current.PID]
		if !relevant {
			continue
		}
		usage := cpu[current.Identity]
		activity.RelevantProcesses = append(activity.RelevantProcesses, Process{
			Process:     current,
			Kind:        class.kind,
			BuildSystem: class.system,
			Project:     class.project,
			CPUPercent:  usage,
		})
		if class.kind == "falcon" {
			activity.FalconCPUPercent += usage
			continue
		}
		activity.BuildCPUPercent += usage
		activity.Immediate = activity.Immediate || class.immediate
		key := class.project + "\x00" + class.system
		score := scores[key]
		score.project = class.project
		score.system = class.system
		score.score += usage
		if class.immediate {
			score.score += 100_000
		}
		scores[key] = score
	}
	best := projectScore{}
	for _, score := range scores {
		if score.score > best.score {
			best = score
		}
	}
	activity.Project = best.project
	activity.BuildSystem = best.system
	activity.Busy = activity.Immediate || activity.BuildCPUPercent >= threshold
	return activity
}

func directClassification(current proc.Process, projectRoot string) (classification, bool) {
	name := strings.ToLower(current.Name)
	base := strings.ToLower(filepath.Base(current.Path))
	arguments := strings.ToLower(strings.Join(current.Args, "\x00"))
	combined := name + " " + base + " " + strings.ToLower(current.Path)
	project := projectForProcess(current, projectRoot)

	if strings.Contains(combined, "com.crowdstrike.falcon.agent") {
		return classification{kind: "falcon"}, true
	}
	if strings.Contains(arguments, "org.gradle.wrapper.gradlewrappermain") ||
		strings.Contains(arguments, "org.gradle.launcher.gradlemain") ||
		name == "gradle" || base == "gradle" || name == "gradlew" || base == "gradlew" {
		return classification{kind: "build-client", system: "gradle", project: project, immediate: true}, true
	}
	if strings.Contains(arguments, "org.gradle.launcher.daemon.bootstrap.gradledaemon") {
		return classification{kind: "build-daemon", system: "gradle", project: project}, true
	}
	if strings.Contains(arguments, "org.jetbrains.kotlin.daemon") || strings.Contains(arguments, "kotlinc") || strings.Contains(name, "kotlin-daemon") {
		return classification{kind: "build-tool", system: "gradle", project: project}, true
	}
	if name == "aapt2" || base == "aapt2" {
		return classification{kind: "build-tool", system: "gradle", project: project}, true
	}
	if project == "" {
		return classification{}, false
	}

	args := lowerArgs(current.Args)
	switch {
	case name == "cargo" || base == "cargo":
		return classification{kind: "build-client", system: "rust", project: project, immediate: hasAny(args, "build", "check", "test", "run", "install")}, true
	case name == "rustc" || base == "rustc":
		return classification{kind: "build-tool", system: "rust", project: project}, true
	case name == "go" || base == "go":
		return classification{kind: "build-client", system: "go", project: project, immediate: hasAny(args, "build", "test", "run", "install", "generate")}, true
	case isOneOf(name, base, "npm", "pnpm", "yarn", "bun", "npx"):
		return classification{kind: "build-client", system: "node", project: project, immediate: hasAny(args, "build", "test", "run", "compile", "bundle")}, true
	case name == "node" || base == "node":
		if hasAny(args, "webpack", "vite", "rollup", "esbuild", "tsc", "jest", "vitest") {
			return classification{kind: "build-tool", system: "node", project: project}, true
		}
	case isOneOf(name, base, "cmake", "ninja", "make", "gmake"):
		return classification{kind: "build-client", system: "native", project: project, immediate: true}, true
	case isOneOf(name, base, "clang", "clang++", "cc", "c++"):
		return classification{kind: "build-tool", system: "native", project: project}, true
	case name == "xcodebuild" || base == "xcodebuild":
		return classification{kind: "build-client", system: "xcode", project: project, immediate: true}, true
	case strings.Contains(name, "swiftc") || strings.Contains(base, "swiftc"):
		return classification{kind: "build-tool", system: "xcode", project: project}, true
	case name == "nix" || base == "nix":
		return classification{kind: "build-client", system: "nix", project: project, immediate: hasAny(args, "build", "develop", "shell", "check")}, true
	}
	return classification{}, false
}

func projectForProcess(current proc.Process, projectRoot string) string {
	if projectRoot == "" {
		return ""
	}
	for _, candidate := range append([]string{current.WorkingDirectory}, current.Args...) {
		candidate = strings.TrimPrefix(candidate, "-Duser.dir=")
		if project := projectFromPath(candidate, projectRoot); project != "" {
			return project
		}
	}
	return ""
}

func projectFromPath(candidate, projectRoot string) string {
	if candidate == "" || !filepath.IsAbs(candidate) {
		return ""
	}
	absoluteRoot, err := filepath.Abs(projectRoot)
	if err != nil {
		return ""
	}
	relative, err := filepath.Rel(absoluteRoot, filepath.Clean(candidate))
	if err != nil || relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return ""
	}
	return strings.Split(relative, string(filepath.Separator))[0]
}

func isBuildTool(current proc.Process) bool {
	name := strings.ToLower(current.Name)
	base := strings.ToLower(filepath.Base(current.Path))
	for _, candidate := range []string{"aapt2", "clang", "clang++", "cmake", "d8", "java", "kotlinc", "ninja", "r8", "rustc", "swiftc", "tsc"} {
		if name == candidate || base == candidate || strings.Contains(name, candidate) {
			return true
		}
	}
	return false
}

func lowerArgs(arguments []string) []string {
	result := make([]string, len(arguments))
	for index, argument := range arguments {
		result[index] = strings.ToLower(argument)
	}
	return result
}

func hasAny(arguments []string, values ...string) bool {
	for _, argument := range arguments {
		for _, value := range values {
			if argument == value || strings.Contains(argument, value) {
				return true
			}
		}
	}
	return false
}

func isOneOf(name, base string, values ...string) bool {
	for _, value := range values {
		if name == value || base == value {
			return true
		}
	}
	return false
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if value != "" {
			return value
		}
	}
	return ""
}
