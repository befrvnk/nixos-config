package app

import (
	"bufio"
	"fmt"
	"io"
	"math"
	"strings"

	"github.com/befrvnk/nixos-config/pkgs/home-cleanup/internal/cleanup"
)

type Dependencies struct {
	Home          string
	Ignores       cleanup.IgnoreChecker
	CurrentStatus func() cleanup.Status
	Remove        cleanup.RemoveFunc
}

type parsedArgs struct {
	command   string
	options   cleanup.Options
	assumeYes bool
	help      bool
}

const usage = `Usage:
  home-cleanup [dry-run]
  home-cleanup clean [--all-gradle] [--projects] [--yes]

Commands:
  dry-run      Show reclaimable space without deleting anything (default)
  clean        Show the dry-run report, ask for confirmation, then remove safe caches

Options for clean:
  --all-gradle Remove all ~/.gradle/caches instead of only build-cache-1
  --projects   Also remove Git-ignored build/ directories under ~/projects
  --yes, -y    Skip the confirmation prompt
  --help, -h   Show this help

The standard cleanup removes Android Studio generated indexes/caches,
Gradle's local build cache, Homebrew downloads, ~/.cache, and npm caches.
Android Studio or Gradle caches are skipped while the corresponding process
is running. Project cleanup only removes build/ directories confirmed ignored
by Git.
`

func parseArgs(args []string) (parsedArgs, error) {
	parsed := parsedArgs{command: "dry-run"}
	if len(args) == 0 {
		return parsed, nil
	}

	parsed.command = args[0]
	args = args[1:]
	switch parsed.command {
	case "help", "--help", "-h":
		if len(args) > 0 {
			return parsedArgs{}, fmt.Errorf("help does not accept options")
		}
		parsed.help = true
		return parsed, nil
	case "dry-run":
		if len(args) > 0 {
			return parsedArgs{}, fmt.Errorf("%s does not accept options", parsed.command)
		}
		return parsed, nil
	case "clean":
	default:
		return parsedArgs{}, fmt.Errorf("unknown command: %s", parsed.command)
	}

	for _, argument := range args {
		switch argument {
		case "--all-gradle":
			parsed.options.AllGradle = true
		case "--projects":
			parsed.options.Projects = true
		case "--yes", "-y":
			parsed.assumeYes = true
		case "--help", "-h":
			parsed.help = true
		default:
			return parsedArgs{}, fmt.Errorf("unknown option for clean: %s", argument)
		}
	}
	return parsed, nil
}

func Run(args []string, input io.Reader, output, errorOutput io.Writer, dependencies Dependencies) int {
	parsed, err := parseArgs(args)
	if err != nil {
		fmt.Fprint(errorOutput, usage)
		fmt.Fprintf(errorOutput, "error: %v\n", err)
		return 2
	}
	if parsed.help {
		fmt.Fprint(output, usage)
		return 0
	}

	home, err := cleanup.CanonicalHome(dependencies.Home)
	if err != nil {
		fmt.Fprintf(errorOutput, "error: resolve home directory: %v\n", err)
		return 1
	}
	fmt.Fprintln(output, "Scanning cleanup candidates; large Gradle caches may take a while...")
	inventory, err := cleanup.Discover(home, dependencies.Ignores)
	if err != nil {
		fmt.Fprintf(errorOutput, "error: discover cleanup candidates: %v\n", err)
		return 1
	}
	status := cleanup.Status{}
	if dependencies.CurrentStatus != nil {
		status = dependencies.CurrentStatus()
	}
	printReport(output, inventory, status)
	if parsed.command != "clean" {
		return 0
	}

	selected := inventory.Selected(parsed.options)
	fmt.Fprintf(output, "\nSelected cleanup: %s\n", FormatBytes(cleanup.SelectedBytes(selected)))
	if !parsed.assumeYes {
		confirmed, confirmErr := confirm(input, output)
		if confirmErr != nil {
			fmt.Fprintln(errorOutput, "error: confirmation failed; pass --yes to run non-interactively")
			return 2
		}
		if !confirmed {
			fmt.Fprintln(output, "Cancelled.")
			return 0
		}
	}

	if dependencies.CurrentStatus != nil {
		status = dependencies.CurrentStatus()
	}
	result, err := cleanup.Execute(home, selected, status, dependencies.Ignores, dependencies.Remove)
	if err != nil {
		fmt.Fprintf(errorOutput, "error: cleanup failed: %v\n", err)
		return 1
	}
	printSkipped(errorOutput, result.Skipped)
	fmt.Fprintf(output, "\nCleanup complete. Targeted %s of files.\n", FormatBytes(result.RemovedBytes))
	fmt.Fprintln(output, "Run home-cleanup again to measure what remains.")
	return 0
}

func confirm(input io.Reader, output io.Writer) (bool, error) {
	fmt.Fprint(output, "Continue? [y/N] ")
	answer, err := bufio.NewReader(input).ReadString('\n')
	if err != nil && len(answer) == 0 {
		return false, err
	}
	switch strings.ToLower(strings.TrimSpace(answer)) {
	case "y", "yes":
		return true, nil
	default:
		return false, nil
	}
}

func printReport(output io.Writer, inventory cleanup.Inventory, status cleanup.Status) {
	fmt.Fprintln(output, "Reclaimable home-directory space")
	fmt.Fprintln(output)
	fmt.Fprintln(output, "Standard cleanup:")
	printSize(output, "Android Studio generated indexes/caches", cleanup.Sum(inventory.AndroidStudio))
	printSize(output, "Gradle local build cache", inventory.GradleBuild.Bytes)
	printSize(output, "Homebrew downloads", inventory.Homebrew.Bytes)
	printSize(output, "User tool caches (~/.cache)", inventory.UserCache.Bytes)
	printSize(output, "npm caches", cleanup.Sum(inventory.NPM))
	fmt.Fprintln(output, "  -----------------------------------------------------------")
	printSize(output, "Standard total", inventory.StandardBytes())

	fmt.Fprintln(output)
	fmt.Fprintln(output, "Optional cleanup:")
	printSize(output, "Other Gradle caches (--all-gradle)", inventory.ExtraGradleBytes())
	printSize(output, "Git-ignored project build directories (--projects)", cleanup.Sum(inventory.ProjectBuilds))
	fmt.Fprintln(output, "  -----------------------------------------------------------")
	printSize(output, "Maximum selected by all options", inventory.MaximumBytes())

	fmt.Fprintln(output)
	fmt.Fprintln(output, "Safety status:")
	if status.AndroidStudioRunning {
		fmt.Fprintln(output, "  Android Studio is running; its cache cleanup will be skipped.")
	} else {
		fmt.Fprintln(output, "  Android Studio is not running.")
	}
	if status.GradleRunning {
		fmt.Fprintln(output, "  A Gradle daemon is running; Gradle cleanup will be skipped.")
	} else {
		fmt.Fprintln(output, "  No Gradle daemon is running.")
	}
	fmt.Fprintf(output, "  Project cleanup found %d Git-ignored build directories.\n", len(inventory.ProjectBuilds))
}

func printSize(output io.Writer, label string, bytes int64) {
	fmt.Fprintf(output, "  %-47s %10s\n", label, FormatBytes(bytes))
}

func printSkipped(output io.Writer, skipped []cleanup.Skip) {
	type summary struct {
		count int
		bytes int64
	}
	byReason := make(map[string]summary)
	for _, item := range skipped {
		current := byReason[item.Reason]
		current.count++
		current.bytes += item.Candidate.Bytes
		byReason[item.Reason] = current
	}
	for _, reason := range []string{
		"Android Studio is running",
		"a Gradle daemon is running",
		"Git ignore status cannot be verified",
		"directory is no longer confirmed ignored by Git",
	} {
		current, exists := byReason[reason]
		if !exists {
			continue
		}
		fmt.Fprintf(output, "Skipped %d path(s), %s: %s.\n", current.count, FormatBytes(current.bytes), reason)
	}
}

func FormatBytes(bytes int64) string {
	if bytes <= 0 {
		return "0B"
	}
	units := []string{"B", "KiB", "MiB", "GiB", "TiB"}
	value := float64(bytes)
	unit := 0
	for value >= 1024 && unit < len(units)-1 {
		value /= 1024
		unit++
	}
	if unit == 0 || value >= 10 || math.Abs(value-math.Round(value)) < 0.05 {
		return fmt.Sprintf("%.0f%s", value, units[unit])
	}
	return fmt.Sprintf("%.1f%s", value, units[unit])
}
