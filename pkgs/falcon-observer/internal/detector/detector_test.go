package detector

import (
	"testing"
	"time"

	proc "github.com/befrvnk/nixos-config/pkgs/falcon-observer/internal/process"
)

func TestClientStartsImmediatelyAndStopsAfterInactivity(t *testing.T) {
	config := Config{
		CPUThreshold:   15,
		TriggerSamples: 3,
		Inactivity:     90 * time.Second,
		MaximumSession: 45 * time.Minute,
	}
	detector := New(config)
	start := time.Unix(1000, 0)

	if transition := detector.Observe(start, Activity{At: start, Busy: true, Immediate: true}); transition != Started {
		t.Fatalf("first transition = %v, want Started", transition)
	}
	if transition := detector.Observe(start.Add(time.Minute), Activity{At: start.Add(time.Minute)}); transition != NoTransition {
		t.Fatalf("transition while entering cooldown = %v", transition)
	}
	if transition := detector.Observe(start.Add(2*time.Minute+31*time.Second), Activity{At: start.Add(2*time.Minute + 31*time.Second)}); transition != StoppedInactive {
		t.Fatalf("final transition = %v, want StoppedInactive", transition)
	}
}

func TestDaemonRequiresSustainedActivity(t *testing.T) {
	detector := New(Config{
		CPUThreshold:   15,
		TriggerSamples: 3,
		Inactivity:     time.Minute,
		MaximumSession: time.Hour,
	})
	start := time.Unix(1000, 0)
	for index := 0; index < 2; index++ {
		at := start.Add(time.Duration(index) * 2 * time.Second)
		if transition := detector.Observe(at, Activity{At: at, Busy: true}); transition != NoTransition {
			t.Fatalf("sample %d transition = %v", index, transition)
		}
	}
	at := start.Add(4 * time.Second)
	if transition := detector.Observe(at, Activity{At: at, Busy: true}); transition != Started {
		t.Fatalf("third transition = %v, want Started", transition)
	}
}

func TestMaximumSessionStopsBusyBuild(t *testing.T) {
	detector := New(Config{
		CPUThreshold:   15,
		TriggerSamples: 1,
		Inactivity:     time.Minute,
		MaximumSession: 10 * time.Minute,
	})
	start := time.Unix(1000, 0)
	detector.Observe(start, Activity{At: start, Busy: true})
	at := start.Add(10 * time.Minute)
	if transition := detector.Observe(at, Activity{At: at, Busy: true}); transition != StoppedMaximumDuration {
		t.Fatalf("transition = %v, want StoppedMaximumDuration", transition)
	}
}

func TestMaximumSessionDoesNotRetriggerUntilGradleBecomesIdle(t *testing.T) {
	detector := New(Config{
		CPUThreshold:   15,
		TriggerSamples: 1,
		Inactivity:     time.Minute,
		MaximumSession: time.Minute,
	})
	start := time.Unix(1000, 0)
	detector.Observe(start, Activity{At: start, Busy: true})
	detector.Observe(start.Add(time.Minute), Activity{At: start.Add(time.Minute), Busy: true})
	if transition := detector.Observe(start.Add(2*time.Minute), Activity{At: start.Add(2 * time.Minute), Busy: true, Immediate: true}); transition != NoTransition {
		t.Fatalf("busy suppressed transition = %v", transition)
	}
	detector.Observe(start.Add(3*time.Minute), Activity{At: start.Add(3 * time.Minute)})
	if transition := detector.Observe(start.Add(4*time.Minute), Activity{At: start.Add(4 * time.Minute), Busy: true}); transition != Started {
		t.Fatalf("post-idle transition = %v, want Started", transition)
	}
}

func TestClassifyGradleAndFalcon(t *testing.T) {
	gradle := proc.Process{
		Identity: proc.Identity{PID: 10, StartTime: 1},
		Name:     "java",
		Path:     "/Library/Java/JavaVirtualMachines/jdk/bin/java",
		Args:     []string{"java", "org.gradle.launcher.daemon.bootstrap.GradleDaemon"},
	}
	falcon := proc.Process{
		Identity: proc.Identity{PID: 20, StartTime: 2},
		Name:     "com.crowdstrike.falcon.Agent",
		Path:     "/Library/SystemExtensions/example/com.crowdstrike.falcon.Agent",
	}
	activity := Classify(time.Unix(1000, 0), []proc.Process{gradle, falcon}, map[proc.Identity]float64{
		gradle.Identity: 80,
		falcon.Identity: 40,
	}, 15)
	if !activity.Busy || activity.Immediate {
		t.Fatalf("activity = %#v, want busy non-immediate", activity)
	}
	if activity.GradleCPUPercent != 80 || activity.FalconCPUPercent != 40 {
		t.Fatalf("unexpected CPU totals: %#v", activity)
	}
}
