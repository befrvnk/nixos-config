package images

import (
	"errors"
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
	DefaultMaxImages = 12
	DefaultMaxBytes  = 15 << 20
	MaxImages        = 20
	MaxBytes         = 30 << 20
)

var galleryElementPattern = regexp.MustCompile(`(?i)<div[^>]*class="[^"]*\bgalleryimage-element\b[^"]*"[^>]*>`)
var galleryImagePattern = regexp.MustCompile(`data-imgsrc="(https://img\.kleinanzeigen\.de/api/v1/prod-ads/images/[0-9a-f]{2}/[0-9a-f-]{36})`)
var listingIDPattern = regexp.MustCompile(`/([0-9]+)-[0-9]+-[0-9]+/?$`)

type Image struct {
	File        string `json:"file"`
	URL         string `json:"url"`
	ContentType string `json:"contentType"`
	Bytes       int64  `json:"bytes"`
}

type Manifest struct {
	SourceURL string  `json:"sourceURL"`
	ListingID string  `json:"listingID"`
	Images    []Image `json:"images"`
}

func Download(rawURL, output string, maxImages int, maxBytes int64) (Manifest, string, error) {
	listingURL, err := parseListingURL(rawURL)
	if err != nil {
		return Manifest{}, "", err
	}
	if maxImages < 1 || maxImages > MaxImages {
		return Manifest{}, "", fmt.Errorf("max images must be between 1 and %d", MaxImages)
	}
	if maxBytes < 1 || maxBytes > MaxBytes {
		return Manifest{}, "", fmt.Errorf("max bytes must be between 1 and %d", MaxBytes)
	}

	client := newClient()
	html, err := fetchListing(client, listingURL)
	if err != nil {
		return Manifest{}, "", err
	}
	urls := extractGalleryURLs(html)
	if len(urls) == 0 {
		return Manifest{}, "", errors.New("no listing gallery images found")
	}
	if len(urls) > maxImages {
		urls = urls[:maxImages]
	}

	id := listingID(listingURL.Path)
	dir, err := makeOutputDir(output, id)
	if err != nil {
		return Manifest{}, "", err
	}
	result := Manifest{SourceURL: listingURL.String(), ListingID: id}
	for index, imageURL := range urls {
		image, err := downloadImage(client, imageURL, dir, index+1, maxBytes)
		if err != nil {
			return Manifest{}, "", fmt.Errorf("download image %d: %w", index+1, err)
		}
		result.Images = append(result.Images, image)
	}
	return result, dir, nil
}

func parseListingURL(rawURL string) (*url.URL, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, fmt.Errorf("invalid URL: %w", err)
	}
	validHost := parsed.Hostname() == "www.kleinanzeigen.de" || parsed.Hostname() == "kleinanzeigen.de"
	if parsed.Scheme != "https" || !validHost || !strings.HasPrefix(parsed.Path, "/s-anzeige/") {
		return nil, errors.New("URL must be an https://www.kleinanzeigen.de/s-anzeige/... listing")
	}
	return parsed, nil
}

func newClient() *http.Client {
	return &http.Client{
		Timeout: 30 * time.Second,
		CheckRedirect: func(request *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("too many redirects")
			}
			host := request.URL.Hostname()
			if request.URL.Scheme != "https" || (host != "www.kleinanzeigen.de" && host != "kleinanzeigen.de") {
				return fmt.Errorf("redirect to unsupported host %q", host)
			}
			return nil
		},
	}
}

func fetchListing(client *http.Client, listingURL *url.URL) ([]byte, error) {
	request, err := http.NewRequest(http.MethodGet, listingURL.String(), nil)
	if err != nil {
		return nil, err
	}
	request.Header.Set("User-Agent", "kleinanzeigen/0.1 (+https://github.com/befrvnk/nixos-config)")
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

func extractGalleryURLs(html []byte) []string {
	starts := galleryElementPattern.FindAllIndex(html, -1)
	seen := make(map[string]struct{}, len(starts))
	urls := make([]string, 0, len(starts))
	for index, start := range starts {
		end := len(html)
		if index+1 < len(starts) {
			end = starts[index+1][0]
		}
		match := galleryImagePattern.FindSubmatch(html[start[0]:end])
		if len(match) != 2 {
			continue
		}
		imageURL := string(match[1])
		if _, exists := seen[imageURL]; !exists {
			seen[imageURL] = struct{}{}
			urls = append(urls, imageURL+"?rule=$_59.JPG")
		}
	}
	return urls
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
		return os.MkdirTemp("", "kleinanzeigen-"+id+"-")
	}
	dir := filepath.Join(output, id)
	return dir, os.MkdirAll(dir, 0o755)
}

func downloadImage(client *http.Client, imageURL, dir string, index int, maxBytes int64) (Image, error) {
	request, err := http.NewRequest(http.MethodGet, imageURL, nil)
	if err != nil {
		return Image{}, err
	}
	request.Header.Set("User-Agent", "kleinanzeigen/0.1 (+https://github.com/befrvnk/nixos-config)")
	response, err := client.Do(request)
	if err != nil {
		return Image{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return Image{}, fmt.Errorf("image request returned %s", response.Status)
	}
	contentType := strings.ToLower(strings.TrimSpace(strings.Split(response.Header.Get("Content-Type"), ";")[0]))
	extension, ok := map[string]string{"image/jpeg": "jpg", "image/png": "png", "image/webp": "webp"}[contentType]
	if !ok {
		return Image{}, fmt.Errorf("unsupported image type %q", contentType)
	}
	file := fmt.Sprintf("image-%02d.%s", index, extension)
	path := filepath.Join(dir, file)
	out, err := os.OpenFile(path, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
	if err != nil {
		return Image{}, err
	}
	written, copyErr := io.Copy(out, io.LimitReader(response.Body, maxBytes+1))
	closeErr := out.Close()
	if copyErr != nil || closeErr != nil || written > maxBytes {
		_ = os.Remove(path)
		if copyErr != nil {
			return Image{}, copyErr
		}
		if closeErr != nil {
			return Image{}, closeErr
		}
		return Image{}, fmt.Errorf("image exceeds %d-byte limit", maxBytes)
	}
	return Image{File: path, URL: imageURL, ContentType: contentType, Bytes: written}, nil
}
