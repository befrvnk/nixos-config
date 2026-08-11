package images

import (
	"reflect"
	"testing"
)

func TestExtractGalleryURLsExcludesRecommendedListings(t *testing.T) {
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
	`)
	want := []string{
		"https://img.kleinanzeigen.de/api/v1/prod-ads/images/aa/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa?rule=$_59.JPG",
		"https://img.kleinanzeigen.de/api/v1/prod-ads/images/bb/bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb?rule=$_59.JPG",
	}
	if got := extractGalleryURLs(html); !reflect.DeepEqual(got, want) {
		t.Errorf("extractGalleryURLs() = %#v, want %#v", got, want)
	}
}

func TestParseListingURL(t *testing.T) {
	if _, err := parseListingURL("https://www.kleinanzeigen.de/s-anzeige/e-bike/3460642230-217-16377"); err != nil {
		t.Fatalf("valid listing URL rejected: %v", err)
	}
	if _, err := parseListingURL("https://example.com/s-anzeige/e-bike/3460642230-217-16377"); err == nil {
		t.Fatal("non-Kleinanzeigen URL accepted")
	}
}
