package listing

import (
	"errors"
	"fmt"
	"html"
	"io"
	"net/http"
	"net/url"
	"regexp"
	"strings"
	"time"
)

var listingIDPattern = regexp.MustCompile(`/([0-9]+)-[0-9]+-[0-9]+/?$`)
var metaPattern = regexp.MustCompile(`(?is)<meta\s+[^>]*>`)
var attributePattern = regexp.MustCompile(`(?i)([a-z:]+)="([^"]*)"`)
var pricePattern = regexp.MustCompile(`(?is)id="viewad-price"[^>]*>\s*([^<]+)`)

type Listing struct {
	ID          string `json:"id"`
	URL         string `json:"url"`
	Title       string `json:"title"`
	Description string `json:"description"`
	Price       string `json:"price,omitempty"`
	Image       string `json:"image,omitempty"`
}

func Fetch(rawURL string) (Listing, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return Listing{}, fmt.Errorf("invalid URL: %w", err)
	}
	if parsed.Scheme != "https" || (parsed.Hostname() != "www.kleinanzeigen.de" && parsed.Hostname() != "kleinanzeigen.de") || !strings.HasPrefix(parsed.Path, "/s-anzeige/") {
		return Listing{}, errors.New("URL must be an https://www.kleinanzeigen.de/s-anzeige/... listing")
	}
	request, err := http.NewRequest(http.MethodGet, parsed.String(), nil)
	if err != nil {
		return Listing{}, err
	}
	request.Header.Set("User-Agent", "kleinanzeigen/0.1 (+https://github.com/befrvnk/nixos-config)")
	client := &http.Client{Timeout: 30 * time.Second}
	response, err := client.Do(request)
	if err != nil {
		return Listing{}, err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return Listing{}, fmt.Errorf("listing request returned %s", response.Status)
	}
	body, err := io.ReadAll(io.LimitReader(response.Body, 5<<20))
	if err != nil {
		return Listing{}, err
	}
	values := openGraph(body)
	id := ""
	if match := listingIDPattern.FindStringSubmatch(parsed.Path); len(match) == 2 {
		id = match[1]
	}
	price := ""
	if match := pricePattern.FindSubmatch(body); len(match) == 2 {
		price = strings.TrimSpace(html.UnescapeString(string(match[1])))
	}
	return Listing{ID: id, URL: parsed.String(), Title: values["og:title"], Description: values["og:description"], Price: price, Image: values["og:image"]}, nil
}

func openGraph(body []byte) map[string]string {
	values := map[string]string{}
	for _, tag := range metaPattern.FindAll(body, -1) {
		attributes := map[string]string{}
		for _, match := range attributePattern.FindAllSubmatch(tag, -1) {
			attributes[strings.ToLower(string(match[1]))] = decodeHTML(string(match[2]))
		}
		if property := attributes["property"]; strings.HasPrefix(property, "og:") {
			values[property] = attributes["content"]
		}
	}
	return values
}

func decodeHTML(value string) string {
	for range 2 {
		decoded := html.UnescapeString(value)
		if decoded == value {
			break
		}
		value = decoded
	}
	return value
}
