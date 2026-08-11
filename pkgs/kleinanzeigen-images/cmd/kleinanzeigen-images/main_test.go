package main

import (
	"reflect"
	"testing"
)

func TestParseListingURL(t *testing.T) {
	valid, err := parseListingURL("https://www.kleinanzeigen.de/s-anzeige/e-bike/1234567890-217-1234")
	if err != nil {
		t.Fatalf("parseListingURL() error = %v", err)
	}
	if valid.Hostname() != "www.kleinanzeigen.de" {
		t.Fatalf("hostname = %q", valid.Hostname())
	}

	for _, rawURL := range []string{
		"http://www.kleinanzeigen.de/s-anzeige/e-bike/1234567890-217-1234",
		"https://example.com/s-anzeige/e-bike/1234567890-217-1234",
		"https://www.kleinanzeigen.de/s-fahrrad/k0",
	} {
		if _, err := parseListingURL(rawURL); err == nil {
			t.Errorf("parseListingURL(%q) succeeded", rawURL)
		}
	}
}

func TestExtractImageURLsUsesOnlyListingGallery(t *testing.T) {
	html := []byte(`
		<div class="galleryimage-element current">
		  <img data-imgsrc="https://img.kleinanzeigen.de/api/v1/prod-ads/images/aa/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa?rule=$_59.AUTO">
		</div>
		<div class="galleryimage-element">
		  <img data-imgsrc="https://img.kleinanzeigen.de/api/v1/prod-ads/images/bb/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?rule=$_59.AUTO">
		</div>
		<div class="recommendation">
		  <img src="https://img.kleinanzeigen.de/api/v1/prod-ads/images/cc/cccccccc-cccc-cccc-cccc-cccccccccccc?rule=$_59.AUTO">
		</div>
		<div class="galleryimage-element">
		  <img data-imgsrc="https://img.kleinanzeigen.de/api/v1/prod-ads/images/aa/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa?rule=$_59.AUTO">
		</div>
	`)
	got := extractImageURLs(html)
	want := []string{
		"https://img.kleinanzeigen.de/api/v1/prod-ads/images/aa/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa?rule=$_59.JPG",
		"https://img.kleinanzeigen.de/api/v1/prod-ads/images/bb/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?rule=$_59.JPG",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("extractImageURLs() = %#v, want %#v", got, want)
	}
}

func TestListingID(t *testing.T) {
	if got := listingID("/s-anzeige/e-bike/3482089832-217-6575"); got != "3482089832" {
		t.Errorf("listingID() = %q, want 3482089832", got)
	}
	if got := listingID("/s-fahrrad/k0"); got != "listing" {
		t.Errorf("listingID() = %q, want listing", got)
	}
}

func TestImageExtension(t *testing.T) {
	for contentType, want := range map[string]string{
		"image/jpeg": "jpg",
		"image/png":  "png",
		"image/webp": "webp",
	} {
		got, ok := imageExtension(contentType)
		if !ok || got != want {
			t.Errorf("imageExtension(%q) = %q, %t; want %q, true", contentType, got, ok, want)
		}
	}
	if _, ok := imageExtension("text/html"); ok {
		t.Error("imageExtension(text/html) succeeded")
	}
}
