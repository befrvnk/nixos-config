package trace

import (
	"bufio"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
)

type Count struct {
	Name  string `json:"name"`
	Count int64  `json:"count"`
}

type Category struct {
	Name             string  `json:"name"`
	PathEvents       int64   `json:"path_events"`
	Opens            int64   `json:"opens"`
	LogicalReadBytes uint64  `json:"logical_read_bytes_approx"`
	OperationSeconds float64 `json:"operation_seconds"`
	TopExtensions    []Count `json:"top_extensions,omitempty"`
}

type Summary struct {
	RawBytes      int64      `json:"raw_bytes"`
	Lines         int64      `json:"lines"`
	FalconLines   int64      `json:"falcon_lines"`
	PathEvents    int64      `json:"path_events"`
	TopOperations []Count    `json:"top_operations,omitempty"`
	Categories    []Category `json:"categories,omitempty"`
}

var (
	operationPattern = regexp.MustCompile(`^\d\d:\d\d:\d\d\.\d+\s+(\S+)`)
	fdPattern        = regexp.MustCompile(`\bF=(\d+)`)
	bytesPattern     = regexp.MustCompile(`\bB=0x([0-9a-fA-F]+)`)
	pathPattern      = regexp.MustCompile(`(/\S.*?)(?:\s{2,})(\d+\.\d{6})\s+(?:W\s+)?com\.crowdstrike`)
)

type categoryData struct {
	Category
	extensions map[string]int64
}

func ParseFile(path, project string) (Summary, error) {
	file, err := os.Open(path)
	if err != nil {
		return Summary{}, err
	}
	defer file.Close()
	info, _ := file.Stat()
	result, err := Parse(file, project)
	if info != nil {
		result.RawBytes = info.Size()
	}
	return result, err
}

func Parse(input io.Reader, project string) (Summary, error) {
	result := Summary{}
	operations := make(map[string]int64)
	categories := make(map[string]*categoryData)
	fds := make(map[int]string)
	scanner := bufio.NewScanner(input)
	scanner.Buffer(make([]byte, 64*1024), 4*1024*1024)
	for scanner.Scan() {
		line := scanner.Text()
		result.Lines++
		if !strings.Contains(line, "com.crowdstrike") {
			continue
		}
		result.FalconLines++
		operationMatch := operationPattern.FindStringSubmatch(line)
		if len(operationMatch) != 2 {
			continue
		}
		operation := operationMatch[1]
		operations[operation]++
		fd := -1
		if match := fdPattern.FindStringSubmatch(line); len(match) == 2 {
			fd, _ = strconv.Atoi(match[1])
		}
		pathMatch := pathPattern.FindStringSubmatch(line)
		if len(pathMatch) == 3 {
			path := pathMatch[1]
			name := categoryForPath(path, project)
			data := categories[name]
			if data == nil {
				data = &categoryData{Category: Category{Name: name}, extensions: make(map[string]int64)}
				categories[name] = data
			}
			data.PathEvents++
			result.PathEvents++
			if seconds, err := strconv.ParseFloat(pathMatch[2], 64); err == nil {
				data.OperationSeconds += seconds
			}
			if strings.HasPrefix(operation, "open") {
				data.Opens++
				data.extensions[extension(path)]++
				if fd >= 0 {
					fds[fd] = name
				}
			}
		}
		if operation == "read" && fd >= 0 {
			if match := bytesPattern.FindStringSubmatch(line); len(match) == 2 {
				if bytes, err := strconv.ParseUint(match[1], 16, 64); err == nil {
					if data := categories[fds[fd]]; data != nil {
						data.LogicalReadBytes += bytes
					}
				}
			}
		}
		if operation == "close" && fd >= 0 {
			delete(fds, fd)
		}
	}
	if err := scanner.Err(); err != nil {
		return result, err
	}
	result.TopOperations = topCounts(operations, 20)
	for _, data := range categories {
		data.TopExtensions = topCounts(data.extensions, 10)
		result.Categories = append(result.Categories, data.Category)
	}
	sort.Slice(result.Categories, func(left, right int) bool {
		return result.Categories[left].PathEvents > result.Categories[right].PathEvents
	})
	return result, nil
}

func categoryForPath(path, project string) string {
	lower := strings.ToLower(path)
	if strings.Contains(lower, "/nix/store/") {
		return "nix-store"
	}
	if strings.Contains(lower, "/projects/") {
		switch {
		case strings.Contains(lower, "/build/"):
			return "project-build-output"
		case strings.Contains(lower, "/.gradle/"):
			return "project-gradle-state"
		case strings.Contains(lower, "/node_modules/"):
			return "project-node-modules"
		case containsDirectory(lower, "target", "dist", "out"):
			return "project-generated-output"
		default:
			return "project-source-or-other"
		}
	}
	if strings.Contains(lower, "/.gradle/caches/") || strings.Contains(lower, "/.gradle/wrapper/") {
		return "global-gradle-cache"
	}
	// Long fs_usage paths can lose their prefix. These markers still identify
	// generated output without persisting the original path.
	if strings.Contains(lower, "/build/intermediates/") || strings.Contains(lower, "/build/tmp/") || strings.Contains(lower, "/build/generated/") {
		return "truncated-project-build-output"
	}
	if strings.Contains(lower, "/users/") && strings.Contains(lower, "/library/") {
		return "user-library"
	}
	if strings.HasPrefix(lower, "/system/") || strings.HasPrefix(lower, "/usr/") || strings.HasPrefix(lower, "/library/") {
		return "macos-system"
	}
	if strings.HasPrefix(lower, "/dev/") {
		return "device-io"
	}
	return "other"
}

func containsDirectory(path string, values ...string) bool {
	for _, value := range values {
		if strings.Contains(path, "/"+value+"/") {
			return true
		}
	}
	return false
}

func extension(path string) string {
	extension := strings.ToLower(filepath.Ext(strings.TrimSpace(path)))
	if extension == "" || len(extension) > 12 {
		return "<none>"
	}
	return extension
}

func topCounts(values map[string]int64, limit int) []Count {
	result := make([]Count, 0, len(values))
	for name, count := range values {
		result = append(result, Count{Name: name, Count: count})
	}
	sort.Slice(result, func(left, right int) bool {
		if result[left].Count == result[right].Count {
			return result[left].Name < result[right].Name
		}
		return result[left].Count > result[right].Count
	})
	if len(result) > limit {
		result = result[:limit]
	}
	return result
}
