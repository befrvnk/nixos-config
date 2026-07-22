package cleanup

import (
	"fmt"
	"path/filepath"
	"strings"
)

type Kind string

const (
	KindAndroidStudio Kind = "android-studio"
	KindGradle        Kind = "gradle"
	KindHomebrew      Kind = "homebrew"
	KindUserCache     Kind = "user-cache"
	KindNPM           Kind = "npm"
	KindProjectBuild  Kind = "project-build"
)

type Candidate struct {
	Kind  Kind
	Path  string
	Bytes int64
}

type Inventory struct {
	AndroidStudio []Candidate
	GradleBuild   Candidate
	GradleAll     Candidate
	Homebrew      Candidate
	UserCache     Candidate
	NPM           []Candidate
	ProjectBuilds []Candidate
}

type Options struct {
	AllGradle bool
	Projects  bool
}

type Status struct {
	AndroidStudioRunning bool
	GradleRunning        bool
}

func Sum(candidates []Candidate) int64 {
	var total int64
	for _, candidate := range candidates {
		total += candidate.Bytes
	}
	return total
}

func (inventory Inventory) StandardBytes() int64 {
	return Sum(inventory.AndroidStudio) + inventory.GradleBuild.Bytes + inventory.Homebrew.Bytes + inventory.UserCache.Bytes + Sum(inventory.NPM)
}

func (inventory Inventory) ExtraGradleBytes() int64 {
	extra := inventory.GradleAll.Bytes - inventory.GradleBuild.Bytes
	if extra < 0 {
		return 0
	}
	return extra
}

func (inventory Inventory) MaximumBytes() int64 {
	return inventory.StandardBytes() + inventory.ExtraGradleBytes() + Sum(inventory.ProjectBuilds)
}

func (inventory Inventory) Selected(options Options) []Candidate {
	selected := make([]Candidate, 0, len(inventory.AndroidStudio)+len(inventory.NPM)+len(inventory.ProjectBuilds)+3)
	selected = append(selected, inventory.AndroidStudio...)
	if options.AllGradle {
		if inventory.GradleAll.Bytes > 0 {
			selected = append(selected, inventory.GradleAll)
		}
	} else if inventory.GradleBuild.Bytes > 0 {
		selected = append(selected, inventory.GradleBuild)
	}
	if inventory.Homebrew.Bytes > 0 {
		selected = append(selected, inventory.Homebrew)
	}
	if inventory.UserCache.Bytes > 0 {
		selected = append(selected, inventory.UserCache)
	}
	selected = append(selected, inventory.NPM...)
	if options.Projects {
		selected = append(selected, inventory.ProjectBuilds...)
	}
	return selected
}

func SelectedBytes(candidates []Candidate) int64 {
	return Sum(candidates)
}

func ValidateHomePath(home, path string) error {
	homeAbs, err := filepath.Abs(home)
	if err != nil {
		return fmt.Errorf("resolve home directory: %w", err)
	}
	if resolved, resolveErr := filepath.EvalSymlinks(homeAbs); resolveErr == nil {
		homeAbs = resolved
	}
	pathAbs, err := filepath.Abs(path)
	if err != nil {
		return fmt.Errorf("resolve cleanup path: %w", err)
	}
	if resolved, resolveErr := filepath.EvalSymlinks(pathAbs); resolveErr == nil {
		pathAbs = resolved
	}
	relative, err := filepath.Rel(homeAbs, pathAbs)
	if err != nil {
		return fmt.Errorf("compare cleanup path to home directory: %w", err)
	}
	if relative == "." || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) {
		return fmt.Errorf("refusing to remove path outside the home directory: %s", path)
	}
	return nil
}
