package messaging

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"

	"github.com/befrvnk/nixos-config/pkgs/kleinanzeigen/internal/auth"
)

func Reply(conversationID, text string) error {
	if conversationID == "" || text == "" {
		return fmt.Errorf("conversation id and message are required")
	}
	token, err := auth.Credentials()
	if err != nil {
		return err
	}
	uid, err := auth.AccountID()
	if err != nil {
		return err
	}
	body, _ := json.Marshal(map[string]string{"message": text})
	u := "https://gateway.kleinanzeigen.de/messagebox/api/users/" + url.PathEscape(uid) + "/conversations/" + url.PathEscape(conversationID) + "?warnPhoneNumber=false&warnEmail=false&warnBankDetails=false"
	r, err := http.NewRequest(http.MethodPost, u, bytes.NewReader(body))
	if err != nil {
		return err
	}
	r.Header.Set("Authorization", "Bearer "+token.AccessToken)
	r.Header.Set("Content-Type", "application/json")
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("reply request returned %s", resp.Status)
	}
	messages, err := Messages(conversationID)
	if err != nil {
		return fmt.Errorf("reply accepted but could not verify it: %w", err)
	}
	for _, m := range messages {
		if m.Direction == "sent" && m.Text == text {
			return nil
		}
	}
	return fmt.Errorf("reply was not found after sending")
}
