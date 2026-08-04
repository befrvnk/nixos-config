package retention

import (
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestApplyRemovesExpiredAndPreservesActiveSession(t *testing.T) {
	root := t.TempDir()
	now := time.Unix(2_000_000, 0)
	expired := createSession(t, root, "session-expired", 10, now.Add(-48*time.Hour))
	active := createSession(t, root, "session-active", 10, now.Add(-48*time.Hour))
	createSession(t, root, "session-current", 10, now.Add(-time.Hour))

	if err := Apply(root, active, now, Config{MaximumAge: 24 * time.Hour}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(expired); !os.IsNotExist(err) {
		t.Fatalf("expired session still exists: %v", err)
	}
	if _, err := os.Stat(active); err != nil {
		t.Fatalf("active session removed: %v", err)
	}
}

func TestActiveSessionCountsTowardSizeLimit(t *testing.T) {
	root := t.TempDir()
	now := time.Unix(2_000_000, 0)
	oldest := createSession(t, root, "session-oldest", 10, now.Add(-3*time.Hour))
	active := createSession(t, root, "session-active", 15, now)

	if err := Apply(root, active, now, Config{MaximumTotalBytes: 20}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(oldest); !os.IsNotExist(err) {
		t.Fatalf("old session still exists: %v", err)
	}
	if _, err := os.Stat(active); err != nil {
		t.Fatalf("active session removed: %v", err)
	}
}

func TestApplyRemovesOldestSessionsToMeetSizeLimit(t *testing.T) {
	root := t.TempDir()
	now := time.Unix(2_000_000, 0)
	oldest := createSession(t, root, "session-oldest", 10, now.Add(-3*time.Hour))
	middle := createSession(t, root, "session-middle", 10, now.Add(-2*time.Hour))
	newest := createSession(t, root, "session-newest", 10, now.Add(-time.Hour))

	if err := Apply(root, "", now, Config{MaximumTotalBytes: 20}); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(oldest); !os.IsNotExist(err) {
		t.Fatalf("oldest session still exists: %v", err)
	}
	for _, path := range []string{middle, newest} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("expected session removed: %s: %v", path, err)
		}
	}
}

func createSession(t *testing.T, root, name string, size int, modified time.Time) string {
	t.Helper()
	path := filepath.Join(root, name)
	if err := os.Mkdir(path, 0o700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(path, "data"), make([]byte, size), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(path, modified, modified); err != nil {
		t.Fatal(err)
	}
	return path
}
