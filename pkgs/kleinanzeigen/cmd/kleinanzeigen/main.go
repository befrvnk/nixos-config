package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"

	"github.com/befrvnk/nixos-config/pkgs/kleinanzeigen/internal/images"
	"github.com/befrvnk/nixos-config/pkgs/kleinanzeigen/internal/listing"
	"github.com/befrvnk/nixos-config/pkgs/kleinanzeigen/internal/search"
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
	case "listing":
		return runListing(args[1:], stdout, stderr)
	case "search":
		return runSearch(args[1:], stdout, stderr)
	case "help", "--help", "-h":
		printUsage(stdout)
		return nil
	default:
		printUsage(stderr)
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func runSearch(args []string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("kleinanzeigen search", flag.ContinueOnError)
	flags.SetOutput(stderr)
	query := flags.String("query", "", "search query")
	location := flags.String("location-id", "", "numeric location id")
	postcode := flags.String("postcode", "", "postcode or place name")
	radius := flags.Int("radius", 50, "radius in km")
	category := flags.Int("category", 217, "category id")
	maxPrice := flags.Int("max-price", 0, "maximum price")
	sort := flags.String("sort", "DATE_DESCENDING", "API sort type")
	jsonOutput := flags.Bool("json", false, "print JSON")
	if err := flags.Parse(args); err != nil {
		return err
	}
	if *query == "" || (*location == "" && *postcode == "") {
		return errors.New("search requires --query and --location-id or --postcode")
	}
	locationID := *location
	if locationID == "" {
		var err error
		locationID, err = search.ResolveLocation(*postcode)
		if err != nil {
			return err
		}
	}
	results, err := search.Fetch(*query, locationID, *radius, *category, *maxPrice, *sort)
	if err != nil {
		return err
	}
	if *jsonOutput {
		return json.NewEncoder(stdout).Encode(results)
	}
	for _, r := range results {
		fmt.Fprintf(stdout, "[%s] %s € | %s %s\n    %s\n    %s\n", r.ID, r.Price, r.ZIP, r.City, r.Title, r.URL)
	}
	return nil
}

func runListing(args []string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("kleinanzeigen listing", flag.ContinueOnError)
	flags.SetOutput(stderr)
	jsonOutput := flags.Bool("json", false, "print listing details as JSON")
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 1 {
		return errors.New("listing requires exactly one listing URL")
	}
	result, err := listing.Fetch(flags.Arg(0))
	if err != nil {
		return err
	}
	if *jsonOutput {
		return json.NewEncoder(stdout).Encode(result)
	}
	_, err = fmt.Fprintf(stdout, "%s\n%s\n%s\n", result.Title, result.Price, result.URL)
	return err
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
	fmt.Fprintln(writer, "  listing <listing-url> Show public listing details")
	fmt.Fprintln(writer, "  search               Search public listings")
	fmt.Fprintln(writer, "  version               Print the CLI version")
}
