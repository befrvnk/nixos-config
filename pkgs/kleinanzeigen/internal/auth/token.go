package auth

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"time"
)

type Token struct {
	AccessToken  string    `json:"accessToken"`
	RefreshToken string    `json:"refreshToken"`
	ExpiresAt    time.Time `json:"expiresAt"`
	Email        string    `json:"email,omitempty"`
	UserID       string    `json:"userId,omitempty"`
}

func Path() (string, error) {
	if p := os.Getenv("KLEINANZEIGEN_TOKEN_FILE"); p != "" {
		return p, nil
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "kleinanzeigen", "token.json"), nil
}
func Load() (Token, error) {
	path, err := Path()
	if err != nil {
		return Token{}, err
	}
	data, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		return Token{}, nil
	}
	if err != nil {
		return Token{}, err
	}
	var token Token
	err = json.Unmarshal(data, &token)
	return token, err
}
func Save(token Token) error {
	path, err := Path()
	if err != nil {
		return err
	}
	if err = os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		return err
	}
	data, err := json.Marshal(token)
	if err != nil {
		return err
	}
	return os.WriteFile(path, data, 0600)
}
func Logout() error {
	path, err := Path()
	if err != nil {
		return err
	}
	err = os.Remove(path)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	return err
}
func (t Token) LoggedIn() bool { return t.RefreshToken != "" }
