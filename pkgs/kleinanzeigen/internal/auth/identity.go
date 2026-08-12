package auth

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"time"
)

func Credentials() (Token, error) {
	token, err := Load()
	if err != nil {
		return Token{}, err
	}
	if !token.LoggedIn() {
		return Token{}, fmt.Errorf("not logged in; run kleinanzeigen login")
	}
	if time.Now().After(token.ExpiresAt.Add(-time.Minute)) {
		return Token{}, fmt.Errorf("access token expired; run kleinanzeigen login")
	}
	return token, nil
}
func AccountID() (string, error) {
	token, err := Credentials()
	if err != nil {
		return "", err
	}
	if token.UserID != "" {
		return token.UserID, nil
	}
	if token.Email == "" {
		return "", fmt.Errorf("token has no email; run kleinanzeigen login again")
	}
	r, err := http.NewRequest(http.MethodGet, "https://api.kleinanzeigen.de/api/users/"+url.PathEscape(token.Email)+"/profile.json", nil)
	if err != nil {
		return "", err
	}
	r.SetBasicAuth("android", "TaR60pEttY")
	r.Header.Set("X-EBAYK-USERID-TOKEN", token.AccessToken)
	r.Header.Set("X-ECG-Authorization-User", "email="+token.Email+",access="+token.AccessToken)
	resp, err := (&http.Client{Timeout: 30 * time.Second}).Do(r)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return "", fmt.Errorf("profile request returned %s", resp.Status)
	}
	var body struct {
		Data struct {
			ID string `json:"id"`
		} `json:"data"`
		ID string `json:"id"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return "", err
	}
	id := body.Data.ID
	if id == "" {
		id = body.ID
	}
	if id == "" {
		return "", fmt.Errorf("profile response contained no account id")
	}
	token.UserID = id
	if err := Save(token); err != nil {
		return "", err
	}
	return id, nil
}
