package powermetrics

import (
	"strings"
	"testing"
)

func TestParse(t *testing.T) {
	input := strings.Join([]string{
		"com.crowdstrike.falcon.Agent 826 1000.00 999.00 80.00 0 0 0 0 1048576.0 1024.0 0.0 42.0",
		"com.crowdstrike.falcon.Agent 826 2000.00 999.00 80.00 0 0 0 0 2097152.0 2048.0 0.0 84.0",
		"fs_usage 10 500.00 499.00 80.00 0 0 0 0 0.0 1048576.0 0.0 10.0",
	}, "\n")
	summary, err := Parse(strings.NewReader(input))
	if err != nil {
		t.Fatal(err)
	}
	if summary.Falcon.MeanCPUPercent != 150 || summary.Falcon.MaximumReadBytesPerSec != 2097152 {
		t.Fatalf("Falcon summary = %#v", summary.Falcon)
	}
	if summary.FSUsage.MeanCPUPercent != 50 {
		t.Fatalf("fs_usage summary = %#v", summary.FSUsage)
	}
}
