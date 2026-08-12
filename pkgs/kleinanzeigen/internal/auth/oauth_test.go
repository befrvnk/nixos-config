package auth

import "testing"

func TestEmailClaim(t *testing.T) {
	if got := emailClaim("header.eyJlbWFpbCI6ImZyYW5rQGV4YW1wbGUuY29tIn0.signature"); got != "frank@example.com" {
		t.Fatalf("emailClaim() = %q", got)
	}
	if got := emailClaim("not-a-jwt"); got != "" {
		t.Fatalf("invalid token = %q", got)
	}
}
