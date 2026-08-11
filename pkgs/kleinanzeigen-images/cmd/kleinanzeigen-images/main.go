package main

import (
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

const (
	defaultMaxImages = 12
	defaultMaxBytes  = 15 << 20
	maxImagesLimit  = 20
	maxBytesLimit   = 30 << 20
)

var imageURLPattern = regexp.MustCompile(`https://img\.kleinanzeigen\.de/api/v1/prod-ads/images/[0-9a-f]{2}/[0-9a-f-]{36}`)
var listingIDPattern = regexp.MustCompile(`/([0-9]+)-[0-9]+-[0-9]+/?$`)

type imageEntry struct {
	File        string `json:"file"`
	URL         string `json:"url"`
	ContentType string `json:"contentType"`
	Bytes       int64  `json:"bytes"`
}

type manifest struct {
	SourceURL string       `json:"sourceURL"`
	ListingID string       `json:"listingID"`
	Images    []imageEntry `json:"images"`
}

func main() {
	if err := run(os.Args[1:], os.Stdout, os.Stderr); err != nil {
		fmt.Fprintln(os.Stderr, "Error:", err)
		os.Exit(1)
	}
}

func run(args []string, stdout, stderr io.Writer) error {
	flags := flag.NewFlagSet("kleinanzeigen-images", flag.ContinueOnError)
	flags.SetOutput(stderr)
	output := flags.String("output", "", "directory for downloaded images (default: a temporary directory)")
	maxImages := flags.Int("max-images", defaultMaxImages, "maximum images to download (1-20)")
	maxBytes := flags.Int64("max-bytes", defaultMaxBytes, "maximum bytes per image (1-31457280)")
	jsonOutput := flags.Bool("json", false, "print the manifest as JSON to stdout")
	flags.Usage = func() {
		fmt.Fprintln(stderr, "Usage: kleinanzeigen-images [options] <Kleinanzeigen listing URL>")
		flags.PrintDefaults()
	}
	if err := flags.Parse(args); err != nil {
		if errors.Is(err, flag.ErrHelp) {
			return nil
		}
		return err
	}
	if flags.NArg() != 1 {
		flags.Usage()
		return errors.New("exactly one listing URL is required")
	}
	if *maxImages < 1 || *maxImages > maxImagesLimit {
		return fmt.Errorf("--max-images must be between 1 and %d", maxImagesLimit)
	}
	if *maxBytes < 1 || *maxBytes > maxBytesLimit {
		return fmt.Errorf("--max-bytes must be between 1 and %d", maxBytesLimit)
	}

	listingURL, err := parseListingURL(flags.Arg(0))
	if err != nil {
		return err
	}
	client := newClient()
	html, err := fetchListing(client, listingURL)
	if err != nil {
		return err
	}
	imageURLs := extractImageURLs(html)
	if len(imageURLs) == 0 {
		return errors.New("no listing images found; Kleinanzeigen may have changed its page format")
	}
	if len(imageURLs) > *maxImages {
		imageURLs = imageURLs[:*maxImages]
	}

	listingID := listingID(listingURL.Path)
	dir, err := makeOutputDir(*output, listingID)
	if err != nil {
		return err
	}
	result := manifest{SourceURL: listingURL.String(), ListingID: listingID}
	for index, imageURL := range imageURLs {
		entry, err := downloadImage(client, imageURL, dir, index+1, *maxBytes)
		if err != nil {
			fmt.Fprintf(stderr, "Warning: image %d was skipped: %v\n", index+1, err)
			continue
		}
		result.Images = append(result.Images, entry)
	}
	if len(result.Images) == 0 {
		return errors.New("could not download any listing images")
	}

	manifestPath := filepath.Join(dir, "manifest.json")
	manifestData, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return err
	}
	if err := os.WriteFile(manifestPath, append(manifestData, '\n'), 0o644); err != nil {
		return err
	}
	if *jsonOutput {
		_, err = stdout.Write(append(manifestData, '\n'))
		return err
	}
	_, err = fmt.Fprintf(stdout, "Downloaded %d image(s) to %s\nManifest: %s\n", len(result.Images), dir, manifestPath)
	return err
}

func newClient() *http.Client {
	return &http.Client{
		Timeout: 30 * time.Second,
		CheckRedirect: func(request *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("too many redirects")
			}
			if request.URL.Scheme != "https" || !isListingHost(request.URL.Hostname()) {
				return fmt.Errorf("redirect to unsupported host %q", request.URL.Hostname())
			}
			return nil
		},
	}
}

func parseListingURL(rawURL string) (*url.URL, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}
	if parsed.Scheme != "https" || !isListingHost(parsed.Hostname()) || !strings.HasPrefix(parsed.Path, "/s-anzeige/") {
		return nil, errors.New("URL must be an https://www.kleinanzeigen.de/s-anzeige/... listing")
	}
	return parsed, nil
}

func isListingHost(host string) bool {
	return host == "www.kleinanzeigen.de" || host == "kleinanzeigen.de"
}

func fetchListing(client *http.Client, listingURL *url.URL) ([]byte, error) {
	request, err := http.NewRequest(http.MethodGet, listingURL.String(), nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", "kleinanzeigen-images/0.1 (+https://github.com/befrvnk/nixos-config)")
	response, err := client.Do(request)
	if err != nil {
		return nil, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("listing request returned %s", response.Status)
	}
	return io.ReadAll(io.LimitReader(response.Body, 5<<20))
}

func extractImageURLs(html []byte) []string {
	seen := make(map[string]struct{})
	var imageURLs []string
	for _, match := range imageURLPattern.FindAllString(string(html), -1) {
		if _, exists := seen[match]; exists {
			continue
		}
		seen[match] = struct{}{}
		imageURLs = append(imageURLs, match+"?rule=$_59.JPG")
	}
	return imageURLs
}

func listingID(path string) string {
	matches := listingIDPattern.FindStringSubmatch(path)
	if len(matches) == 2 {
		return matches[1]
	}
	return "listing"
}

func makeOutputDir(output, id string) (string, error) {
	if output == "" {
		return os.MkdirTemp("", "kleinanzeigen-images-"+id+"-")
	}
	dir := filepath.Join(output, id)
	return dir, os.MkdirAll(dir, 0o755)
}

func downloadImage(client *http.Client, imageURL, dir string, index int, maxBytes int64) (imageEntry, error) {
	parsed, err := url.Parse(imageURL)
	if err != nil {
		return imageEntry{}, err
	}
	if parsed.Scheme != "https" || parsed.Hostname() != "img.kleinanzeigen.de" {
		return imageEntry{}, errors.New("image URL has an unsupported host")
	}
	request, err := http.NewRequest(http.MethodGet, imageURL, nil)
	if err != nil {
		return imageEntry{}, err
	}
	request.Header.Set("User-Agent", "kleinanzeigen-images/0.1 (+https://github.com/befrvnk/nixos-config)")
	response, err := client.Do(request)
	if err != nil {
		return imageEntry{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return imageEntry{}, fmt.Errorf("image request returned %s", response.Status)
	}
	contentType := strings.ToLower(strings.TrimSpace(strings.Split(response.Header.Get("Content-Type"), ";")[0]))
	extension, ok := imageExtension(contentType)
	if !ok {
		return imageEntry{}, fmt.Errorf("unsupported image content type %q", contentType)
	}
	file := fmt.Sprintf("image-%02d.%s", index, extension)
	path := filepath.Join(dir, file)
	output, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return imageEntry{}, err
	}
	written, copyErr := io.Copy(output, io.LimitReader(response.Body, maxBytes+1))
	closeErr := output.Close()
	if copyErr != nil || closeErr != nil {
		_ = os.Remove(path)
		if copyErr != nil {
			return imageEntry{}, copyErr
		}
		return imageEntry{}, closeErr
	}
	if written > maxBytes {
		_ = os.Remove(path)
		return imageEntry{}, fmt.Errorf("image exceeds %d-byte limit", maxBytes)
	}
	return imageEntry{File: path, URL: imageURL, ContentType: contentType, Bytes: written}, nil
}

func imageExtension(contentType string) (string, bool) {
	extensions := map[string]string{
		"image/jpeg": "jpg",
		"image/png":  "png",
		"image/webp": "webp",
	}
	extension, ok := extensions[contentType]
	return extension, ok
}
