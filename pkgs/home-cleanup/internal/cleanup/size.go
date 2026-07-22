package cleanup

import (
	"bytes"
	"fmt"
	"os/exec"
	"strconv"
)

func directorySizes(paths []string) (map[string]int64, error) {
	result := make(map[string]int64, len(paths))
	if len(paths) == 0 {
		return result, nil
	}
	arguments := append([]string{"-sk", "--null", "--"}, paths...)
	output, commandErr := exec.Command("du", arguments...).Output()
	for _, record := range bytes.Split(output, []byte{0}) {
		if len(record) == 0 {
			continue
		}
		fields := bytes.SplitN(record, []byte{'\t'}, 2)
		if len(fields) != 2 {
			continue
		}
		kibibytes, err := strconv.ParseInt(string(fields[0]), 10, 64)
		if err != nil {
			return nil, fmt.Errorf("parse du size for %s: %w", fields[1], err)
		}
		result[string(fields[1])] = kibibytes * 1024
	}
	if commandErr != nil && len(result) == 0 {
		return nil, commandErr
	}
	return result, nil
}

func directorySize(path string) (int64, error) {
	sizes, err := directorySizes([]string{path})
	return sizes[path], err
}
