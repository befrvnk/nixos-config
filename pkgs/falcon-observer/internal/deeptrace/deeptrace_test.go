package deeptrace

import (
	"testing"
	"time"
)

func TestDailyRateLimitIsPerProject(t *testing.T) {
	root := t.TempDir()
	now := time.Unix(1000, 0)
	first, err := ShouldRun(root, "app", "gradle", ModeDaily, 24*time.Hour, now)
	if err != nil || !first {
		t.Fatalf("first = %t, err = %v", first, err)
	}
	second, err := ShouldRun(root, "app", "gradle", ModeDaily, 24*time.Hour, now.Add(time.Hour))
	if err != nil || second {
		t.Fatalf("second = %t, err = %v", second, err)
	}
	if err := Request(root, "app", "gradle"); err != nil {
		t.Fatal(err)
	}
	requested, err := ShouldRun(root, "app", "gradle", ModeOff, 24*time.Hour, now.Add(time.Hour))
	if err != nil || !requested {
		t.Fatalf("requested = %t, err = %v", requested, err)
	}
	other, err := ShouldRun(root, "other", "gradle", ModeDaily, 24*time.Hour, now.Add(time.Hour))
	if err != nil || !other {
		t.Fatalf("other = %t, err = %v", other, err)
	}
}
