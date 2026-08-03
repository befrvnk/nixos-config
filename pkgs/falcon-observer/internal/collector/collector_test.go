package collector

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func TestDisabledSessionDoesNotStartCommands(t *testing.T) {
	session, err := Start(Config{Enabled: false}, t.TempDir())
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
	if err := stopCommand(command); err != nil {
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
