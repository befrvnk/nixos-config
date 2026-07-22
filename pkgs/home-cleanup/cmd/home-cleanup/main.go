package main

import (
	"os"

	"github.com/befrvnk/nixos-config/pkgs/home-cleanup/internal/app"
	"github.com/befrvnk/nixos-config/pkgs/home-cleanup/internal/cleanup"
)

func main() {
	home, err := os.UserHomeDir()
	if err != nil {
		os.Stderr.WriteString("error: determine home directory: " + err.Error() + "\n")
		os.Exit(1)
	}

	os.Exit(app.Run(
		os.Args[1:],
		os.Stdin,
		os.Stdout,
		os.Stderr,
		app.Dependencies{
			Home:          home,
			Ignores:       cleanup.GitIgnoreChecker{},
			CurrentStatus: cleanup.DetectStatus,
		},
	))
}
