package retention

import (
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"time"
)

type Config struct {
	MaximumAge        time.Duration
	MaximumTotalBytes int64
}

type directory struct {
	path    string
	modTime time.Time
	size    int64
	active  bool
}

func Reserve(root string, now time.Time, config Config, bytes int64) error {
	reserved := config
	if reserved.MaximumTotalBytes > 0 {
		if bytes >= reserved.MaximumTotalBytes {
			return fmt.Errorf("requested reservation %d exceeds retention budget %d", bytes, reserved.MaximumTotalBytes)
		}
		reserved.MaximumTotalBytes -= bytes
	}
	return Apply(root, "", now, reserved)
}

func Apply(root, active string, now time.Time, config Config) error {
	entries, err := os.ReadDir(root)
	if err != nil {
		if os.IsNotExist(err) {
			return nil
		}
		return fmt.Errorf("read retention root: %w", err)
	}

	var directories []directory
	for _, entry := range entries {
		if !entry.IsDir() || !strings.HasPrefix(entry.Name(), "session-") {
			continue
		}
		path := filepath.Join(root, entry.Name())
		info, err := entry.Info()
		if err != nil {
			return fmt.Errorf("stat session %s: %w", path, err)
		}
		size, err := directorySize(path)
		if err != nil {
			return err
		}
		directories = append(directories, directory{
			path: path, modTime: info.ModTime(), size: size, active: samePath(path, active),
		})
	}
	sort.Slice(directories, func(left, right int) bool {
		return directories[left].modTime.Before(directories[right].modTime)
	})

	removed := make(map[string]bool)
	if config.MaximumAge > 0 {
		cutoff := now.Add(-config.MaximumAge)
		for _, candidate := range directories {
			if candidate.active || !candidate.modTime.Before(cutoff) {
				continue
			}
			if err := os.RemoveAll(candidate.path); err != nil {
				return fmt.Errorf("remove expired session %s: %w", candidate.path, err)
			}
			removed[candidate.path] = true
		}
	}

	if config.MaximumTotalBytes <= 0 {
		return nil
	}
	var total int64
	for _, candidate := range directories {
		if !removed[candidate.path] {
			total += candidate.size
		}
	}
	for _, candidate := range directories {
		if total <= config.MaximumTotalBytes {
			break
		}
		if candidate.active || removed[candidate.path] {
			continue
		}
		if err := os.RemoveAll(candidate.path); err != nil {
			return fmt.Errorf("remove oversized session %s: %w", candidate.path, err)
		}
		total -= candidate.size
	}
	return nil
}

func directorySize(root string) (int64, error) {
	var total int64
	err := filepath.WalkDir(root, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if entry.Type().IsRegular() {
			info, err := entry.Info()
			if err != nil {
				return err
			}
			total += info.Size()
		}
		return nil
	})
	if err != nil {
		return 0, fmt.Errorf("measure session %s: %w", root, err)
	}
	return total, nil
}

func samePath(left, right string) bool {
	if right == "" {
		return false
	}
	absoluteLeft, leftErr := filepath.Abs(left)
	absoluteRight, rightErr := filepath.Abs(right)
	return leftErr == nil && rightErr == nil && absoluteLeft == absoluteRight
}
