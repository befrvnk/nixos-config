package listing

import "testing"

func TestOpenGraph(t *testing.T) {
	values := openGraph([]byte(`
		<meta content="i:SY E-Bike" property="og:title">
		<meta property="og:description" content="Riemen &amp; Enviolo">
		<meta property="og:image" content="https://img.example/image.jpg">
	`))
	if values["og:title"] != "i:SY E-Bike" {
		t.Errorf("title = %q", values["og:title"])
	}
	if values["og:description"] != "Riemen & Enviolo" {
		t.Errorf("description = %q", values["og:description"])
	}
}
