package cleanup

import (
	"errors"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
)

type fakeIgnoreChecker struct {
	ignored map[string]bool
	err     error
}

func (checker fakeIgnoreChecker) IsIgnored(path string) (bool, error) {
	if checker.err != nil {
		return false, checker.err
	}
	return checker.ignored[path], nil
}

func writeFile(t *testing.T, path string, size int) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	data := make([]byte, size)
	if err := os.WriteFile(path, data, 0o644); err != nil {
		t.Fatal(err)
	}
}

func canonicalTempHome(t *testing.T) string {
	t.Helper()
	home, err := CanonicalHome(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	return home
}

func TestDiscoverFindsCachesAndOnlyIgnoredProjectBuilds(t *testing.T) {
	home := canonicalTempHome(t)
	paths := []string{
		filepath.Join(home, "Library/Caches/Google/AndroidStudio2026.1.4/caches/data"),
		filepath.Join(home, "Library/Caches/Google/AndroidStudio2026.1.4/index/data"),
		filepath.Join(home, ".gradle/caches/build-cache-1/data"),
		filepath.Join(home, ".gradle/caches/9.6.1/data"),
		filepath.Join(home, "Library/Caches/Homebrew/downloads/archive"),
		filepath.Join(home, ".cache/tool/data"),
		filepath.Join(home, ".npm/_cacache/data"),
		filepath.Join(home, ".npm/_npx/data"),
	}
	for _, path := range paths {
		writeFile(t, path, 4096)
	}
	ignoredBuild := filepath.Join(home, "projects", "with spaces", "module", "build")
	notIgnoredBuild := filepath.Join(home, "projects", "kept", "build")
	prunedBuild := filepath.Join(home, "projects", "demo", "node_modules", "dependency", "build")
	writeFile(t, filepath.Join(ignoredBuild, "output"), 4096)
	writeFile(t, filepath.Join(notIgnoredBuild, "source"), 4096)
	writeFile(t, filepath.Join(prunedBuild, "output"), 4096)

	inventory, err := Discover(home, fakeIgnoreChecker{ignored: map[string]bool{ignoredBuild: true}})
	if err != nil {
		t.Fatal(err)
	}
	if len(inventory.AndroidStudio) != 2 {
		t.Fatalf("expected two Android Studio candidates, got %d", len(inventory.AndroidStudio))
	}
	if len(inventory.NPM) != 2 {
		t.Fatalf("expected two npm candidates, got %d", len(inventory.NPM))
	}
	if len(inventory.ProjectBuilds) != 1 || inventory.ProjectBuilds[0].Path != ignoredBuild {
		t.Fatalf("unexpected project candidates: %#v", inventory.ProjectBuilds)
	}
	if inventory.StandardBytes() <= 0 || inventory.MaximumBytes() <= inventory.StandardBytes() {
		t.Fatalf("unexpected totals: standard=%d maximum=%d", inventory.StandardBytes(), inventory.MaximumBytes())
	}
}

func TestGitIgnoreCheckerBatchesPathsWithSpaces(t *testing.T) {
	root := canonicalTempHome(t)
	if output, err := exec.Command("git", "-C", root, "init", "-q").CombinedOutput(); err != nil {
		t.Fatalf("git init: %v: %s", err, output)
	}
	if err := os.WriteFile(filepath.Join(root, ".gitignore"), []byte("build/\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	ignoredBuild := filepath.Join(root, "module with spaces", "build")
	keptDirectory := filepath.Join(root, "module", "outputs")
	writeFile(t, filepath.Join(ignoredBuild, "output"), 4096)
	writeFile(t, filepath.Join(keptDirectory, "source"), 4096)

	ignored, err := (GitIgnoreChecker{}).Ignored([]string{ignoredBuild, keptDirectory})
	if err != nil {
		t.Fatal(err)
	}
	if !ignored[ignoredBuild] {
		t.Fatal("expected build directory to be ignored")
	}
	if ignored[keptDirectory] {
		t.Fatal("unexpected ignored result for kept directory")
	}
}

func TestSelectedReplacesBuildCacheWithAllGradleCaches(t *testing.T) {
	inventory := Inventory{
		GradleBuild: Candidate{Kind: KindGradle, Path: "/home/test/.gradle/caches/build-cache-1", Bytes: 40},
		GradleAll:   Candidate{Kind: KindGradle, Path: "/home/test/.gradle/caches", Bytes: 100},
		Homebrew:    Candidate{Kind: KindHomebrew, Path: "/home/test/brew", Bytes: 20},
		ProjectBuilds: []Candidate{
			{Kind: KindProjectBuild, Path: "/home/test/projects/demo/build", Bytes: 30},
		},
	}

	standard := inventory.Selected(Options{})
	if got := SelectedBytes(standard); got != 60 {
		t.Fatalf("standard selection = %d, want 60", got)
	}
	aggressive := inventory.Selected(Options{AllGradle: true, Projects: true})
	if got := SelectedBytes(aggressive); got != 150 {
		t.Fatalf("aggressive selection = %d, want 150", got)
	}
	for _, candidate := range aggressive {
		if candidate.Path == inventory.GradleBuild.Path {
			t.Fatal("all-gradle selection must not also contain the nested build cache")
		}
	}
}

func TestExecutePreservesGradleWrappersAndManagedJDKs(t *testing.T) {
	home := canonicalTempHome(t)
	buildCache := filepath.Join(home, ".gradle", "caches", "build-cache-1")
	wrapper := filepath.Join(home, ".gradle", "wrapper", "dists", "gradle")
	jdk := filepath.Join(home, ".gradle", "jdks", "jdk")
	writeFile(t, filepath.Join(buildCache, "entry"), 4096)
	writeFile(t, wrapper, 4096)
	writeFile(t, jdk, 4096)

	result, err := Execute(home, []Candidate{{Kind: KindGradle, Path: buildCache, Bytes: 4096}}, Status{}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if result.RemovedBytes != 4096 {
		t.Fatalf("removed bytes = %d", result.RemovedBytes)
	}
	if _, err := os.Stat(buildCache); !os.IsNotExist(err) {
		t.Fatalf("build cache still exists: %v", err)
	}
	for _, path := range []string{wrapper, jdk} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("preserved path %s: %v", path, err)
		}
	}
}

func TestAllGradleCleanupStillPreservesWrappersAndManagedJDKs(t *testing.T) {
	home := canonicalTempHome(t)
	caches := filepath.Join(home, ".gradle", "caches")
	wrapper := filepath.Join(home, ".gradle", "wrapper", "dists", "gradle")
	jdk := filepath.Join(home, ".gradle", "jdks", "jdk")
	writeFile(t, filepath.Join(caches, "build-cache-1", "entry"), 4096)
	writeFile(t, filepath.Join(caches, "9.6.1", "entry"), 4096)
	writeFile(t, wrapper, 4096)
	writeFile(t, jdk, 4096)

	_, err := Execute(home, []Candidate{{Kind: KindGradle, Path: caches, Bytes: 8192}}, Status{}, nil, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(caches); !os.IsNotExist(err) {
		t.Fatalf("Gradle caches still exist: %v", err)
	}
	for _, path := range []string{wrapper, jdk} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("preserved path %s: %v", path, err)
		}
	}
}

func TestExecuteSkipsActiveProcessesAndRechecksProjects(t *testing.T) {
	home := canonicalTempHome(t)
	android := filepath.Join(home, "Library", "Caches", "Google", "AndroidStudio", "index")
	gradle := filepath.Join(home, ".gradle", "caches", "build-cache-1")
	project := filepath.Join(home, "projects", "demo", "build")
	for _, path := range []string{android, gradle, project} {
		writeFile(t, filepath.Join(path, "data"), 4096)
	}

	candidates := []Candidate{
		{Kind: KindAndroidStudio, Path: android, Bytes: 1},
		{Kind: KindGradle, Path: gradle, Bytes: 2},
		{Kind: KindProjectBuild, Path: project, Bytes: 3},
	}
	result, err := Execute(
		home,
		candidates,
		Status{AndroidStudioRunning: true, GradleRunning: true},
		fakeIgnoreChecker{ignored: map[string]bool{}},
		nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.RemovedBytes != 0 || len(result.Skipped) != 3 {
		t.Fatalf("unexpected result: %#v", result)
	}
	for _, path := range []string{android, gradle, project} {
		if _, err := os.Stat(path); err != nil {
			t.Fatalf("skipped path %s was removed: %v", path, err)
		}
	}
}

func TestExecuteRemovesProjectBuildWhenStillIgnored(t *testing.T) {
	home := canonicalTempHome(t)
	project := filepath.Join(home, "projects", "demo", "build")
	writeFile(t, filepath.Join(project, "output"), 4096)

	result, err := Execute(
		home,
		[]Candidate{{Kind: KindProjectBuild, Path: project, Bytes: 4096}},
		Status{},
		fakeIgnoreChecker{ignored: map[string]bool{project: true}},
		nil,
	)
	if err != nil {
		t.Fatal(err)
	}
	if result.RemovedBytes != 4096 {
		t.Fatalf("removed bytes = %d", result.RemovedBytes)
	}
	if _, err := os.Stat(project); !os.IsNotExist(err) {
		t.Fatalf("ignored project build still exists: %v", err)
	}
}

func TestExecuteRejectsPathsOutsideHome(t *testing.T) {
	home := canonicalTempHome(t)
	outside := canonicalTempHome(t)
	path := filepath.Join(outside, "cache")
	writeFile(t, filepath.Join(path, "data"), 4096)

	_, err := Execute(home, []Candidate{{Kind: KindUserCache, Path: path, Bytes: 1}}, Status{}, nil, nil)
	if err == nil {
		t.Fatal("expected an outside-home error")
	}
	if _, statErr := os.Stat(path); statErr != nil {
		t.Fatalf("outside path was modified: %v", statErr)
	}
}

func TestExecuteRejectsPathsThroughSymlinksOutsideHome(t *testing.T) {
	home := canonicalTempHome(t)
	outside := canonicalTempHome(t)
	outsideCache := filepath.Join(outside, "cache")
	writeFile(t, filepath.Join(outsideCache, "data"), 4096)
	link := filepath.Join(home, "linked")
	if err := os.Symlink(outside, link); err != nil {
		t.Fatal(err)
	}

	_, err := Execute(home, []Candidate{{Kind: KindUserCache, Path: filepath.Join(link, "cache"), Bytes: 1}}, Status{}, nil, nil)
	if err == nil {
		t.Fatal("expected a symlink escape error")
	}
	if _, statErr := os.Stat(outsideCache); statErr != nil {
		t.Fatalf("outside path was modified: %v", statErr)
	}
}

func TestExecutePropagatesRemovalErrors(t *testing.T) {
	home := canonicalTempHome(t)
	path := filepath.Join(home, ".cache")
	writeFile(t, filepath.Join(path, "data"), 4096)
	expected := errors.New("remove failed")

	_, err := Execute(home, []Candidate{{Kind: KindUserCache, Path: path, Bytes: 1}}, Status{}, nil, func(string) error {
		return expected
	})
	if !errors.Is(err, expected) {
		t.Fatalf("error = %v, want %v", err, expected)
	}
}
