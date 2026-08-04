package deeptrace

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"time"
)

const (
	ModeOff    = "off"
	ModeDaily  = "daily"
	ModeAlways = "always"
)

type state struct {
	Projects  map[string]time.Time `json:"projects"`
	Requested map[string]bool      `json:"requested,omitempty"`
}

func ValidateMode(mode string) error {
	switch mode {
	case ModeOff, ModeDaily, ModeAlways:
		return nil
	default:
		return fmt.Errorf("deep trace mode must be off, daily, or always")
	}
}

func Request(root, project, buildSystem string) error {
	current, err := load(root)
	if err != nil {
		return err
	}
	current.Requested[key(project, buildSystem)] = true
	return save(root, current)
}

func ShouldRun(root, project, buildSystem, mode string, interval time.Duration, now time.Time) (bool, error) {
	if err := ValidateMode(mode); err != nil {
		return false, err
	}
	identifier := key(project, buildSystem)
	current, err := load(root)
	if err != nil {
		return false, err
	}
	if current.Requested[identifier] {
		delete(current.Requested, identifier)
		current.Projects[identifier] = now
		return true, save(root, current)
	}
	if mode == ModeOff {
		return false, nil
	}
	if mode == ModeAlways {
		current.Projects[identifier] = now
		return true, save(root, current)
	}
	if previous, exists := current.Projects[identifier]; exists && now.Sub(previous) < interval {
		return false, nil
	}
	current.Projects[identifier] = now
	return true, save(root, current)
}

func key(project, buildSystem string) string {
	if project == "" {
		project = "unknown"
	}
	if buildSystem == "" {
		buildSystem = "unknown"
	}
	return project + ":" + buildSystem
}

func load(root string) (state, error) {
	result := state{Projects: make(map[string]time.Time), Requested: make(map[string]bool)}
	content, err := os.ReadFile(filepath.Join(root, "deep-trace-state.json"))
	if os.IsNotExist(err) {
		return result, nil
	}
	if err != nil {
		return result, err
	}
	if err := json.Unmarshal(content, &result); err != nil {
		return state{}, err
	}
	if result.Projects == nil {
		result.Projects = make(map[string]time.Time)
	}
	if result.Requested == nil {
		result.Requested = make(map[string]bool)
	}
	return result, nil
}

func save(root string, value state) error {
	if err := os.MkdirAll(root, 0o700); err != nil {
		return err
	}
	content, err := json.MarshalIndent(value, "", "  ")
	if err != nil {
		return err
	}
	content = append(content, '\n')
	temporary := filepath.Join(root, ".deep-trace-state.json.tmp")
	if err := os.WriteFile(temporary, content, 0o600); err != nil {
		return err
	}
	return os.Rename(temporary, filepath.Join(root, "deep-trace-state.json"))
}
