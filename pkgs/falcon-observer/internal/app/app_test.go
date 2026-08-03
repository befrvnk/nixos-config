package app

import (
	"bytes"
	"context"
	"strings"
	"testing"
	"time"
)

func TestVersion(t *testing.T) {
	previous := Version
	Version = "test-version"
	defer func() { Version = previous }()
	var stdout, stderr bytes.Buffer
	if code := Run(context.Background(), []string{"version"}, &stdout, &stderr); code != 0 {
		t.Fatalf("exit code = %d, stderr = %s", code, stderr.String())
	}
	if stdout.String() != "test-version\n" {
		t.Fatalf("stdout = %q", stdout.String())
	}
}

func TestValidateDurations(t *testing.T) {
	if err := validateDurations(2*time.Second, time.Minute, 10*time.Second, 3, 3); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name string
		err  error
	}{
		{"short poll", validateDurations(10*time.Millisecond, time.Minute, time.Second, 1, 1)},
		{"zero maximum", validateDurations(time.Second, 0, time.Second, 1, 1)},
		{"zero samples", validateDurations(time.Second, time.Minute, time.Second, 0, 1)},
	} {
		if test.err == nil {
			t.Errorf("%s unexpectedly passed", test.name)
		}
	}
}

func TestUnknownCommand(t *testing.T) {
	var stdout, stderr bytes.Buffer
	if code := Run(context.Background(), []string{"unknown"}, &stdout, &stderr); code != 2 {
		t.Fatalf("exit code = %d", code)
	}
	if !strings.Contains(stderr.String(), "unknown command") {
		t.Fatalf("stderr = %q", stderr.String())
	}
}
