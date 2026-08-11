package auth

import (
	"bufio"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"
)

const clientID = "uV5j90myVPc2XzEOFuWUD2At17OACEGQ"
const redirectURI = "https://login.kleinanzeigen.de/android/com.ebay.kleinanzeigen/callback"

func Login() error {
	verifier := randomURL(32)
	challenge := hash(verifier)
	state := randomURL(16)
	values := url.Values{"client_id": {clientID}, "response_type": {"code"}, "redirect_uri": {redirectURI}, "scope": {"openid email profile offline_access"}, "code_challenge": {challenge}, "code_challenge_method": {"S256"}, "state": {state}, "prompt": {"login"}}
	fmt.Fprintln(os.Stdout, "Open this URL and sign in to Kleinanzeigen:\n\nhttps://login.kleinanzeigen.de/authorize?"+values.Encode()+"\n\nPaste the full callback URL:")
	redirect, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return err
	}
	parsed, err := url.Parse(strings.TrimSpace(redirect))
	if err != nil {
		return err
	}
	if parsed.Query().Get("state") != state {
		return fmt.Errorf("login state mismatch")
	}
	code := parsed.Query().Get("code")
	if code == "" {
		return fmt.Errorf("callback URL contains no code")
	}
	form := url.Values{"grant_type": {"authorization_code"}, "client_id": {clientID}, "code": {code}, "code_verifier": {verifier}, "redirect_uri": {redirectURI}}
	response, err := http.PostForm("https://login.kleinanzeigen.de/oauth/token", form)
	if err != nil {
		return err
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return fmt.Errorf("token request returned %s", response.Status)
	}
	var payload struct {
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
		ExpiresIn    int    `json:"expires_in"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		return err
	}
	if payload.RefreshToken == "" {
		return fmt.Errorf("token response contains no refresh token")
	}
	return Save(Token{AccessToken: payload.AccessToken, RefreshToken: payload.RefreshToken, ExpiresAt: time.Now().Add(time.Duration(payload.ExpiresIn) * time.Second)})
}
func randomURL(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}
func hash(value string) string {
	sum := sha256.Sum256([]byte(value))
	return base64.RawURLEncoding.EncodeToString(sum[:])
}
