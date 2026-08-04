package trace

import (
	"strings"
	"testing"
)

func TestParseAggregatesWithoutPersistingPaths(t *testing.T) {
	input := strings.Join([]string{
		"09:58:34.375882  openat F=8 (R______________)  [-2]//Users/frank/projects/app/build/classes/A.class  0.000032   com.crowdstrike.fal.7177",
		"09:58:34.375955  read F=8 B=0x506  0.000051   com.crowdstrike.fal.7177",
		"09:58:34.376668  close F=8  0.000002   com.crowdstrike.fal.7177",
		"09:58:34.377000  open F=9 (R______________)  /nix/store/hash-jdk/lib/a.jar  0.000010   com.crowdstrike.fal.7177",
	}, "\n")
	summary, err := Parse(strings.NewReader(input), "app")
	if err != nil {
		t.Fatal(err)
	}
	if summary.FalconLines != 4 || summary.PathEvents != 2 {
		t.Fatalf("summary = %#v", summary)
	}
	for _, category := range summary.Categories {
		if category.Name == "project-build-output" {
			if category.LogicalReadBytes != 0x506 {
				t.Fatalf("project reads = %d", category.LogicalReadBytes)
			}
			return
		}
	}
	t.Fatalf("categories = %#v", summary.Categories)
}
