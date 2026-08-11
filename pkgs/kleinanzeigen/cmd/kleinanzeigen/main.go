package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/befrvnk/nixos-config/pkgs/kleinanzeigen/internal/images"
)

const version = "0.1.0"

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer) error {
	if len(args) == 0 {
		printUsage(stderr)
		return errors.New("a command is required")
	}
	switch args[0] {
	case "version":
		_, err := fmt.Fprintln(stdout, version)
		return err
	case "images":
		return runImages(args[1:], stdout, stderr)
	case "help", "--help", "-h":
		printUsage(stdout)
		return nil
	default:
		printUsage(stderr)
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func runImages(args []string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("kleinanzeigen images", flag.ContinueOnError)
	flags.SetOutput(stderr)
	output := flags.String("output", "", "directory for downloaded images (default: temporary directory)")
	maxImages := flags.Int("max-images", images.DefaultMaxImages, "maximum images to download (1-20)")
	maxBytes := flags.Int64("max-bytes", images.DefaultMaxBytes, "maximum bytes per image (1-31457280)")
	jsonOutput := flags.Bool("json", false, "print the manifest as JSON")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 1 {
		return errors.New("images requires exactly one listing URL")
	}
	manifest, dir, err := images.Download(flags.Arg(0), *output, *maxImages, *maxBytes)
	if err != nil {
		return err
	}
	if *jsonOutput {
		return json.NewEncoder(stdout).Encode(manifest)
	}
	_, err = fmt.Fprintf(stdout, "Downloaded %d image(s) to %s\n", len(manifest.Images), dir)
	return err
}

func printUsage(writer io.Writer) {
	fmt.Fprintln(writer, "Usage: kleinanzeigen <command> [options]")
	fmt.Fprintln(writer, "\nCommands:")
	fmt.Fprintln(writer, "  images <listing-url>  Download images from a listing gallery")
	fmt.Fprintln(writer, "  version               Print the CLI version")
}
