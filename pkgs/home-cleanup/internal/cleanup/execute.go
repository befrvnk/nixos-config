package cleanup

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"syscall"
)

type Skip struct {
	Candidate Candidate
	Reason    string
}

type Result struct {
	RemovedBytes int64
	Skipped      []Skip
}

type RemoveFunc func(path string) error

func clearDirectoryContents(path string, remove RemoveFunc) (bool, error) {
	const attempts = 3
	for range attempts {
		entries, err := os.ReadDir(path)
		if os.IsNotExist(err) {
			return true, nil
		}
		if err != nil {
			return false, err
		}
		if len(entries) == 0 {
			return true, nil
		}
		for _, entry := range entries {
			err := remove(filepath.Join(path, entry.Name()))
			if err == nil || os.IsNotExist(err) || errors.Is(err, syscall.ENOTEMPTY) {
				continue
			}
			return false, err
		}
	}
	entries, err := os.ReadDir(path)
	if os.IsNotExist(err) {
		return true, nil
	}
	return len(entries) == 0, err
}

func Execute(home string, candidates []Candidate, status Status, ignores IgnoreChecker, remove RemoveFunc) (Result, error) {
	if remove == nil {
		remove = os.RemoveAll
	}

	projectPaths := make([]string, 0)
	for _, item := range candidates {
		if item.Kind == KindProjectBuild {
			projectPaths = append(projectPaths, item.Path)
		}
	}
	projectIgnored := map[string]bool{}
	var projectIgnoreErr error
	if len(projectPaths) > 0 && ignores != nil {
		projectIgnored, projectIgnoreErr = ignoredPaths(ignores, projectPaths)
	}

	result := Result{}
	for _, item := range candidates {
		if item.Bytes <= 0 {
			continue
		}
		if item.Kind == KindAndroidStudio && status.AndroidStudioRunning {
			result.Skipped = append(result.Skipped, Skip{Candidate: item, Reason: "Android Studio is running"})
			continue
		}
		if item.Kind == KindGradle && status.GradleRunning {
			result.Skipped = append(result.Skipped, Skip{Candidate: item, Reason: "a Gradle daemon is running"})
			continue
		}
		if item.Kind == KindProjectBuild {
			if ignores == nil {
				result.Skipped = append(result.Skipped, Skip{Candidate: item, Reason: "Git ignore status cannot be verified"})
				continue
			}
			if projectIgnoreErr != nil || !projectIgnored[item.Path] {
				result.Skipped = append(result.Skipped, Skip{Candidate: item, Reason: "directory is no longer confirmed ignored by Git"})
				continue
			}
		}
		if err := ValidateHomePath(home, item.Path); err != nil {
			return result, err
		}
		if item.Kind == KindUserCache {
			complete, err := clearDirectoryContents(item.Path, remove)
			if err != nil {
				return result, fmt.Errorf("clear %s: %w", item.Path, err)
			}
			if !complete {
				result.Skipped = append(result.Skipped, Skip{Candidate: item, Reason: "cache contents changed while cleanup was running"})
				continue
			}
		} else if err := remove(item.Path); err != nil {
			return result, fmt.Errorf("remove %s: %w", item.Path, err)
		}
		result.RemovedBytes += item.Bytes
	}
	return result, nil
}
