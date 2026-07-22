package cleanup

import (
	"fmt"
	"os"
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
		if err := remove(item.Path); err != nil {
			return result, fmt.Errorf("remove %s: %w", item.Path, err)
		}
		result.RemovedBytes += item.Bytes
	}
	return result, nil
}
