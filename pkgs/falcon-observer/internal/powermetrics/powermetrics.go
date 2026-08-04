package powermetrics

import (
	"bufio"
	"io"
	"os"
	"sort"
	"strconv"
	"strings"
)

type Process struct {
	Samples                int     `json:"samples"`
	MeanCPUPercent         float64 `json:"mean_cpu_percent"`
	P95CPUPercent          float64 `json:"p95_cpu_percent"`
	MaximumCPUPercent      float64 `json:"maximum_cpu_percent"`
	MeanReadBytesPerSec    float64 `json:"mean_read_bytes_per_second"`
	MaximumReadBytesPerSec float64 `json:"maximum_read_bytes_per_second"`
	MeanWriteBytesPerSec   float64 `json:"mean_write_bytes_per_second"`
	MeanEnergyImpact       float64 `json:"mean_energy_impact"`
}

type Summary struct {
	Falcon       Process `json:"falcon"`
	FSUsage      Process `json:"fs_usage"`
	Powermetrics Process `json:"powermetrics"`
}

type samples struct {
	cpu, read, write, energy []float64
}

func ParseFile(path string) (Summary, error) {
	file, err := os.Open(path)
	if err != nil {
		return Summary{}, err
	}
	defer file.Close()
	return Parse(file)
}

func Parse(input io.Reader) (Summary, error) {
	values := map[string]*samples{
		"com.crowdstrike.falcon.Agent": {},
		"fs_usage":                     {},
		"powermetrics":                 {},
	}
	scanner := bufio.NewScanner(input)
	for scanner.Scan() {
		line := scanner.Text()
		for name, sample := range values {
			if !strings.HasPrefix(line, name+" ") {
				continue
			}
			fields := strings.Fields(line)
			if len(fields) < 13 {
				continue
			}
			cpu, cpuErr := strconv.ParseFloat(fields[2], 64)
			read, readErr := strconv.ParseFloat(fields[9], 64)
			write, writeErr := strconv.ParseFloat(fields[10], 64)
			energy, energyErr := strconv.ParseFloat(fields[12], 64)
			if cpuErr != nil || readErr != nil || writeErr != nil || energyErr != nil {
				continue
			}
			sample.cpu = append(sample.cpu, cpu/10) // CPU ms/s to percent of one core.
			sample.read = append(sample.read, read)
			sample.write = append(sample.write, write)
			sample.energy = append(sample.energy, energy)
		}
	}
	if err := scanner.Err(); err != nil {
		return Summary{}, err
	}
	return Summary{
		Falcon:       summarize(values["com.crowdstrike.falcon.Agent"]),
		FSUsage:      summarize(values["fs_usage"]),
		Powermetrics: summarize(values["powermetrics"]),
	}, nil
}

func summarize(values *samples) Process {
	return Process{
		Samples:                len(values.cpu),
		MeanCPUPercent:         mean(values.cpu),
		P95CPUPercent:          percentile(values.cpu, .95),
		MaximumCPUPercent:      maximum(values.cpu),
		MeanReadBytesPerSec:    mean(values.read),
		MaximumReadBytesPerSec: maximum(values.read),
		MeanWriteBytesPerSec:   mean(values.write),
		MeanEnergyImpact:       mean(values.energy),
	}
}

func mean(values []float64) float64 {
	if len(values) == 0 {
		return 0
	}
	var total float64
	for _, value := range values {
		total += value
	}
	return total / float64(len(values))
}

func maximum(values []float64) float64 {
	var result float64
	for _, value := range values {
		if value > result {
			result = value
		}
	}
	return result
}

func percentile(values []float64, percentile float64) float64 {
	if len(values) == 0 {
		return 0
	}
	copy := append([]float64(nil), values...)
	sort.Float64s(copy)
	index := int(percentile * float64(len(copy)-1))
	return copy[index]
}
