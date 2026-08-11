package search

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"strconv"
	"strings"
	"time"
)

type Result struct {
	ID    string `json:"id"`
	Title string `json:"title"`
	Price string `json:"price"`
	URL   string `json:"url"`
	ZIP   string `json:"zip"`
	City  string `json:"city"`
}

func ResolveLocation(query string) (string, error) {
	request, err := http.NewRequest(http.MethodGet, "https://api.kleinanzeigen.de/api/locations.json?q="+url.QueryEscape(query), nil)
	if err != nil {
		return "", err
	}
	setHeaders(request)
	response, err := (&http.Client{Timeout: 30 * time.Second}).Do(request)
	if err != nil {
		return "", err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return "", fmt.Errorf("location lookup returned %s", response.Status)
	}
	var root map[string]any
	if err := json.NewDecoder(response.Body).Decode(&root); err != nil {
		return "", err
	}
	locations, _ := root["{http://www.ebayclassifiedsgroup.com/schema/location/v1}locations"].(map[string]any)
	value, _ := locations["value"].(map[string]any)
	raw, _ := value["location"].([]any)
	if len(raw) == 0 {
		return "", fmt.Errorf("no location found for %q", query)
	}
	location, _ := raw[0].(map[string]any)
	id := val(location["id"])
	if id == "" {
		return "", fmt.Errorf("location lookup returned no id for %q", query)
	}
	return id, nil
}

func Fetch(query, locationID string, radius, category, maxPrice int, sort string) ([]Result, error) {
	v := url.Values{"page": {"0"}, "size": {"25"}, "q": {query}, "locationId": {locationID}, "distance": {strconv.Itoa(radius)}, "categoryId": {strconv.Itoa(category)}, "adType": {"OFFERED"}, "sortType": {sort}}
	if maxPrice > 0 {
		v.Set("maxPrice", strconv.Itoa(maxPrice))
	}
	r, err := http.NewRequest(http.MethodGet, "https://api.kleinanzeigen.de/api/ads.json?"+v.Encode(), nil)
	if err != nil {
		return nil, err
	}
	setHeaders(r)
	c := &http.Client{Timeout: 30 * time.Second}
	resp, err := c.Do(r)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, fmt.Errorf("search returned %s", resp.Status)
	}
	var root map[string]any
	if err := json.NewDecoder(resp.Body).Decode(&root); err != nil {
		return nil, err
	}
	block, _ := root["{http://www.ebayclassifiedsgroup.com/schema/ad/v1}ads"].(map[string]any)
	value, _ := block["value"].(map[string]any)
	raw, _ := value["ad"].([]any)
	out := make([]Result, 0, len(raw))
	for _, item := range raw {
		if ad, ok := item.(map[string]any); ok {
			out = append(out, parse(ad))
		}
	}
	return out, nil
}
func setHeaders(request *http.Request) {
	request.SetBasicAuth("android", "TaR60pEttY")
	request.Header.Set("X-EBAYK-APP", fmt.Sprintf("ka%d", time.Now().UnixMilli()))
	request.Header.Set("X-ECG-USER-AGENT", "ebayk-android-app-2026.25.0")
	request.Header.Set("X-ECG-USER-VERSION", "2026.25.0")
	request.Header.Set("User-Agent", "Kleinanzeigen/2026.25.0 (Android 13; Pixel 7)")
}

func val(v any) string {
	if m, ok := v.(map[string]any); ok {
		return val(m["value"])
	}
	if s, ok := v.(string); ok {
		return s
	}
	if n, ok := v.(json.Number); ok {
		return n.String()
	}
	if n, ok := v.(float64); ok {
		return strconv.FormatFloat(n, 'f', -1, 64)
	}
	return ""
}
func parse(ad map[string]any) Result {
	r := Result{ID: val(ad["id"]), Title: val(ad["title"])}
	if p, ok := ad["price"].(map[string]any); ok {
		if wrapped, ok := p["value"].(map[string]any); ok {
			p = wrapped
		}
		r.Price = val(p["amount"])
	}
	if a, ok := ad["ad-address"].(map[string]any); ok {
		r.ZIP = val(a["zip-code"])
		r.City = val(a["state"])
	}
	if links, ok := ad["link"].([]any); ok {
		for _, x := range links {
			if m, ok := x.(map[string]any); ok && val(m["rel"]) == "self-public-website" {
				r.URL = val(m["href"])
			}
		}
	}
	r.Title = strings.TrimSpace(r.Title)
	return r
}
