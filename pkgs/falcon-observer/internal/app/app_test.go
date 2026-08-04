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

func TestValidateConfig(t *testing.T) {
	if err := validateConfig(2*time.Second, time.Minute, 10*time.Second, time.Minute, 3, 3, "daily"); err != nil {
		t.Fatal(err)
	}
	for _, test := range []struct {
		name string
		err  error
	}{
		{"short poll", validateConfig(10*time.Millisecond, time.Minute, time.Second, time.Minute, 1, 1, "daily")},
		{"zero maximum", validateConfig(time.Second, 0, time.Second, time.Minute, 1, 1, "daily")},
		{"zero samples", validateConfig(time.Second, time.Minute, time.Second, time.Minute, 0, 1, "daily")},
		{"invalid deep mode", validateConfig(time.Second, time.Minute, time.Second, time.Minute, 1, 1, "invalid")},
	} {
		if test.err == nil {
			t.Errorf("%s unexpectedly passed", test.name)
		}
	}
}

func TestRequestDeepTrace(t *testing.T) {
	var stdout, stderr bytes.Buffer
	root := t.TempDir()
	code := Run(context.Background(), []string{
		"request-deep-trace", "--output-dir", root, "--project", "app", "--build-system", "gradle",
	}, &stdout, &stderr)
	if code != 0 || !strings.Contains(stdout.String(), "app") {
		t.Fatalf("code = %d, stdout = %q, stderr = %q", code, stdout.String(), stderr.String())
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
