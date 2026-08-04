package collector

import (
	"os"
	"path/filepath"
	"strings"
	"syscall"
	"testing"
	"time"
)

func TestDisabledSessionDoesNotStartCommands(t *testing.T) {
	session, err := Start(Config{Enabled: false}, t.TempDir(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(session.commands) != 0 {
		t.Fatalf("started %d commands with collectors disabled", len(session.commands))
	}
	if err := session.Stop(); err != nil {
		t.Fatal(err)
	}
}

func TestDeepTraceControlsFSUsage(t *testing.T) {
	config := Config{
		Enabled: true, FalconctlPath: "/usr/bin/true", FSUsagePath: "/usr/bin/true",
		PowermetricsPath: "/usr/bin/true", SamplePath: "/usr/bin/true", FSUsageDuration: time.Second,
	}
	standard, err := Start(config, t.TempDir(), false)
	if err != nil {
		t.Fatal(err)
	}
	if len(standard.commands) != 1 || standard.Status().DeepTrace {
		t.Fatalf("standard commands = %d, status = %#v", len(standard.commands), standard.Status())
	}
	_ = standard.Stop()

	deep, err := Start(config, t.TempDir(), true)
	if err != nil {
		t.Fatal(err)
	}
	if len(deep.commands) != 2 || !deep.Status().DeepTrace {
		t.Fatalf("deep commands = %d, status = %#v", len(deep.commands), deep.Status())
	}
	_ = deep.Stop()
}

func TestStartCommandCapturesOutputAndStopsCleanly(t *testing.T) {
	logPath := filepath.Join(t.TempDir(), "command.log")
	command, err := startCommand(
		"helper",
		os.Args[0],
		[]string{"-test.run=TestCollectorHelperProcess", "--", "expected-argument"},
		logPath,
	)
	if err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(2 * time.Second)
	var content []byte
	for time.Now().Before(deadline) {
		content, _ = os.ReadFile(logPath)
		if strings.Contains(string(content), "expected-argument") {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err := stopCommand(command, syscall.SIGTERM); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(content), "expected-argument") {
		t.Fatalf("command output = %q", content)
	}
	info, err := os.Stat(logPath)
	if err != nil {
		t.Fatal(err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Fatalf("log permissions = %o, want 600", info.Mode().Perm())
	}
}

func TestCollectorHelperProcess(t *testing.T) {
	for index, argument := range os.Args {
		if argument == "--" && index+1 < len(os.Args) {
			_, _ = os.Stdout.WriteString(os.Args[index+1] + "\n")
			return
		}
	}
}
