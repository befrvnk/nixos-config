package app

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/befrvnk/nixos-config/pkgs/home-cleanup/internal/cleanup"
)

type ignoreNothing struct{}

func (ignoreNothing) IsIgnored(string) (bool, error) { return false, nil }

func createCache(t *testing.T, home string) string {
	t.Helper()
	path := filepath.Join(home, ".cache", "tool", "data")
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, make([]byte, 4096), 0o644); err != nil {
		t.Fatal(err)
	}
	return filepath.Join(home, ".cache")
}

func TestReportDoesNotDelete(t *testing.T) {
	home := t.TempDir()
	cache := createCache(t, home)
	var output bytes.Buffer
	removeCalls := 0

	exitCode := Run(nil, strings.NewReader(""), &output, &bytes.Buffer{}, Dependencies{
		Home:    home,
		Ignores: ignoreNothing{},
		Remove: func(string) error {
			removeCalls++
			return nil
		},
	})
	if exitCode != 0 {
		t.Fatalf("exit code = %d", exitCode)
	}
	if removeCalls != 0 {
		t.Fatalf("report invoked removal %d times", removeCalls)
	}
	if _, err := os.Stat(cache); err != nil {
		t.Fatalf("report changed cache: %v", err)
	}
	if !strings.Contains(output.String(), "Standard total") {
		t.Fatalf("missing report output: %s", output.String())
	}
}

func TestCleanDefaultsToCancellation(t *testing.T) {
	home := t.TempDir()
	cache := createCache(t, home)
	var output bytes.Buffer
	removeCalls := 0

	exitCode := Run([]string{"clean"}, strings.NewReader("n\n"), &output, &bytes.Buffer{}, Dependencies{
		Home:    home,
		Ignores: ignoreNothing{},
		Remove: func(string) error {
			removeCalls++
			return nil
		},
	})
	if exitCode != 0 || removeCalls != 0 {
		t.Fatalf("exit=%d removeCalls=%d", exitCode, removeCalls)
	}
	if _, err := os.Stat(cache); err != nil {
		t.Fatalf("cancelled cleanup changed cache: %v", err)
	}
	if !strings.Contains(output.String(), "Cancelled.") {
		t.Fatalf("missing cancellation output: %s", output.String())
	}
}

func TestCleanYesRemovesSelectedCache(t *testing.T) {
	home := t.TempDir()
	cache := createCache(t, home)
	var output bytes.Buffer
	var errorOutput bytes.Buffer

	exitCode := Run([]string{"clean", "--yes"}, strings.NewReader(""), &output, &errorOutput, Dependencies{
		Home:    home,
		Ignores: ignoreNothing{},
	})
	if exitCode != 0 {
		t.Fatalf("exit=%d stderr=%s", exitCode, errorOutput.String())
	}
	if _, err := os.Stat(cache); !os.IsNotExist(err) {
		t.Fatalf("cache still exists: %v", err)
	}
	if !strings.Contains(output.String(), "Cleanup complete") {
		t.Fatalf("missing completion output: %s", output.String())
	}
}

func TestCleanRechecksProcessStatusBeforeDeletion(t *testing.T) {
	home := t.TempDir()
	androidCache := filepath.Join(home, "Library", "Caches", "Google", "AndroidStudio2026.1.4", "index")
	data := filepath.Join(androidCache, "data")
	if err := os.MkdirAll(androidCache, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(data, make([]byte, 4096), 0o644); err != nil {
		t.Fatal(err)
	}
	statusChecks := 0
	var errorOutput bytes.Buffer

	exitCode := Run([]string{"clean", "--yes"}, strings.NewReader(""), &bytes.Buffer{}, &errorOutput, Dependencies{
		Home:    home,
		Ignores: ignoreNothing{},
		CurrentStatus: func() cleanup.Status {
			statusChecks++
			return cleanup.Status{AndroidStudioRunning: statusChecks > 1}
		},
	})
	if exitCode != 0 {
		t.Fatalf("exit=%d stderr=%s", exitCode, errorOutput.String())
	}
	if statusChecks != 2 {
		t.Fatalf("status checks = %d, want 2", statusChecks)
	}
	if _, err := os.Stat(androidCache); err != nil {
		t.Fatalf("cache was removed after Android Studio started: %v", err)
	}
	if !strings.Contains(errorOutput.String(), "Android Studio is running") {
		t.Fatalf("missing skip reason: %s", errorOutput.String())
	}
}

func TestCleanWithoutInteractiveInputFailsSafely(t *testing.T) {
	home := t.TempDir()
	cache := createCache(t, home)
	var errorOutput bytes.Buffer

	exitCode := Run([]string{"clean"}, strings.NewReader(""), &bytes.Buffer{}, &errorOutput, Dependencies{
		Home:    home,
		Ignores: ignoreNothing{},
	})
	if exitCode != 2 {
		t.Fatalf("exit code = %d, want 2", exitCode)
	}
	if _, err := os.Stat(cache); err != nil {
		t.Fatalf("non-interactive cleanup changed cache: %v", err)
	}
	if !strings.Contains(errorOutput.String(), "pass --yes") {
		t.Fatalf("missing safety hint: %s", errorOutput.String())
	}
}

func TestUnknownOptionReturnsUsageError(t *testing.T) {
	var errorOutput bytes.Buffer
	exitCode := Run([]string{"clean", "--unknown"}, strings.NewReader(""), &bytes.Buffer{}, &errorOutput, Dependencies{})
	if exitCode != 2 {
		t.Fatalf("exit code = %d, want 2", exitCode)
	}
	if !strings.Contains(errorOutput.String(), "unknown option") {
		t.Fatalf("missing option error: %s", errorOutput.String())
	}
}

func TestFormatBytes(t *testing.T) {
	for _, test := range []struct {
		bytes int64
		want  string
	}{
		{0, "0B"},
		{1024, "1KiB"},
		{6*1024*1024 + 512*1024, "6.5MiB"},
		{134 * 1024 * 1024 * 1024, "134GiB"},
	} {
		if got := FormatBytes(test.bytes); got != test.want {
			t.Errorf("FormatBytes(%d) = %q, want %q", test.bytes, got, test.want)
		}
	}
}

var _ cleanup.IgnoreChecker = ignoreNothing{}
