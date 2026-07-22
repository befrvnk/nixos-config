package cleanup

import (
	"bytes"
	"errors"
	"os"
	"os/exec"
	"path/filepath"
)

type IgnoreChecker interface {
	IsIgnored(path string) (bool, error)
}

type BatchIgnoreChecker interface {
	Ignored(paths []string) (map[string]bool, error)
}

type GitIgnoreChecker struct{}

func (checker GitIgnoreChecker) IsIgnored(path string) (bool, error) {
	ignored, err := checker.Ignored([]string{path})
	return ignored[path], err
}

func (GitIgnoreChecker) Ignored(paths []string) (map[string]bool, error) {
	result := make(map[string]bool, len(paths))
	type repositoryPaths struct {
		absoluteByRelative map[string]string
		input              bytes.Buffer
	}
	byRepository := make(map[string]*repositoryPaths)

	for _, path := range paths {
		root := findRepositoryRoot(path)
		if root == "" {
			continue
		}
		relative, err := filepath.Rel(root, path)
		if err != nil {
			return nil, err
		}
		relative = filepath.ToSlash(relative) + "/"
		group := byRepository[root]
		if group == nil {
			group = &repositoryPaths{absoluteByRelative: make(map[string]string)}
			byRepository[root] = group
		}
		group.absoluteByRelative[relative] = path
		group.input.WriteString(relative)
		group.input.WriteByte(0)
	}

	for root, group := range byRepository {
		command := exec.Command("git", "-C", root, "check-ignore", "-z", "--stdin")
		command.Stdin = bytes.NewReader(group.input.Bytes())
		output, err := command.Output()
		if err != nil {
			var exitError *exec.ExitError
			if errors.As(err, &exitError) && exitError.ExitCode() == 1 {
				continue
			}
			return nil, err
		}
		for _, relative := range bytes.Split(output, []byte{0}) {
			if len(relative) == 0 {
				continue
			}
			if absolute, exists := group.absoluteByRelative[string(relative)]; exists {
				result[absolute] = true
			}
		}
	}
	return result, nil
}

func findRepositoryRoot(path string) string {
	current := filepath.Dir(path)
	for {
		if _, err := os.Lstat(filepath.Join(current, ".git")); err == nil {
			return current
		}
		parent := filepath.Dir(current)
		if parent == current {
			return ""
		}
		current = parent
	}
}

func ignoredPaths(checker IgnoreChecker, paths []string) (map[string]bool, error) {
	if batch, ok := checker.(BatchIgnoreChecker); ok {
		return batch.Ignored(paths)
	}
	result := make(map[string]bool, len(paths))
	for _, path := range paths {
		ignored, err := checker.IsIgnored(path)
		if err != nil {
			return nil, err
		}
		result[path] = ignored
	}
	return result, nil
}

func CanonicalHome(home string) (string, error) {
	absolute, err := filepath.Abs(home)
	if err != nil {
		return "", err
	}
	resolved, err := filepath.EvalSymlinks(absolute)
	if err != nil {
		return "", err
	}
	return resolved, nil
}

func candidate(kind Kind, path string) Candidate {
	if _, err := os.Lstat(path); err != nil {
		return Candidate{Kind: kind, Path: path}
	}
	bytes, err := directorySize(path)
	if err != nil {
		return Candidate{Kind: kind, Path: path}
	}
	return Candidate{Kind: kind, Path: path, Bytes: bytes}
}

func existingCandidates(kind Kind, paths []string) []Candidate {
	existing := make([]string, 0, len(paths))
	for _, path := range paths {
		if _, err := os.Lstat(path); err == nil {
			existing = append(existing, path)
		}
	}
	sizes, _ := directorySizes(existing)
	result := make([]Candidate, 0, len(existing))
	for _, path := range existing {
		if sizes[path] > 0 {
			result = append(result, Candidate{Kind: kind, Path: path, Bytes: sizes[path]})
		}
	}
	return result
}

func discoverGradle(home string) (Candidate, Candidate) {
	root := filepath.Join(home, ".gradle", "caches")
	all := Candidate{Kind: KindGradle, Path: root}
	build := Candidate{Kind: KindGradle, Path: filepath.Join(root, "build-cache-1")}
	entries, err := os.ReadDir(root)
	if err != nil {
		return build, all
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		paths = append(paths, filepath.Join(root, entry.Name()))
	}
	for _, item := range existingCandidates(KindGradle, paths) {
		all.Bytes += item.Bytes
		if filepath.Base(item.Path) == "build-cache-1" {
			build = item
		}
	}
	return build, all
}

func Discover(home string, ignores IgnoreChecker) (Inventory, error) {
	home, err := CanonicalHome(home)
	if err != nil {
		return Inventory{}, err
	}

	inventory := Inventory{}
	androidRoots, err := filepath.Glob(filepath.Join(home, "Library", "Caches", "Google", "AndroidStudio*"))
	if err != nil {
		return Inventory{}, err
	}
	androidPaths := make([]string, 0, len(androidRoots)*2)
	for _, root := range androidRoots {
		androidPaths = append(androidPaths, filepath.Join(root, "caches"), filepath.Join(root, "index"))
	}
	inventory.AndroidStudio = existingCandidates(KindAndroidStudio, androidPaths)

	inventory.GradleBuild, inventory.GradleAll = discoverGradle(home)
	inventory.Homebrew = candidate(KindHomebrew, filepath.Join(home, "Library", "Caches", "Homebrew", "downloads"))
	inventory.UserCache = candidate(KindUserCache, filepath.Join(home, ".cache"))
	inventory.NPM = existingCandidates(KindNPM, []string{
		filepath.Join(home, ".npm", "_cacache"),
		filepath.Join(home, ".npm", "_npx"),
	})

	projectsRoot := filepath.Join(home, "projects")
	if ignores == nil {
		return inventory, nil
	}
	if info, statErr := os.Stat(projectsRoot); statErr != nil || !info.IsDir() {
		return inventory, nil
	}

	pruned := map[string]bool{
		".git": true, ".gradle": true, ".kotlin": true, ".devenv": true,
		".direnv": true, "node_modules": true,
	}
	var buildPaths []string
	err = filepath.WalkDir(projectsRoot, func(path string, entry os.DirEntry, walkErr error) error {
		if walkErr != nil {
			if entry != nil && entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		if !entry.IsDir() {
			return nil
		}
		if path != projectsRoot && pruned[entry.Name()] {
			return filepath.SkipDir
		}
		if entry.Name() != "build" {
			return nil
		}

		buildPaths = append(buildPaths, path)
		return filepath.SkipDir
	})
	if err != nil {
		return Inventory{}, err
	}
	ignored, err := ignoredPaths(ignores, buildPaths)
	if err != nil {
		return Inventory{}, err
	}
	ignoredBuildPaths := make([]string, 0, len(buildPaths))
	for _, path := range buildPaths {
		if ignored[path] {
			ignoredBuildPaths = append(ignoredBuildPaths, path)
		}
	}
	inventory.ProjectBuilds = existingCandidates(KindProjectBuild, ignoredBuildPaths)
	return inventory, nil
}
