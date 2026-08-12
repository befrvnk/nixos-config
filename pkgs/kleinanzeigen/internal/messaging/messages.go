package messaging

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"
	"sort"
	"strings"

	"github.com/befrvnk/nixos-config/pkgs/kleinanzeigen/internal/auth"
)

type Message struct {
	ID        string `json:"id"`
	Text      string `json:"text"`
	Direction string `json:"direction"`
	CreatedAt string `json:"createdAt"`
}

func Messages(conversationID string) ([]Message, error) {
	if conversationID == "" {
		return nil, fmt.Errorf("conversation id is required")
	}
	token, err := auth.Credentials()
	if err != nil {
		return nil, err
	}
	uid, err := auth.AccountID()
	if err != nil {
		return nil, err
	}
	u := "https://gateway.kleinanzeigen.de/messagebox/api/users/" + url.PathEscape(uid) + "/conversations/" + url.PathEscape(conversationID) + "?contentWarnings=true"
	r, err := http.NewRequest(http.MethodPut, u, nil)
	if err != nil {
		return nil, err
	}
	r.Header.Set("Authorization", "Bearer "+token.AccessToken)
	r.Header.Set("Accept", "application/json")
	resp, err := http.DefaultClient.Do(r)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("messages request returned %s", resp.Status)
	}
	var body struct {
		Messages []struct {
			ID        string `json:"id"`
			Text      string `json:"text"`
			Message   string `json:"message"`
			Boundness string `json:"boundness"`
			Direction string `json:"direction"`
			CreatedAt string `json:"receivedDate"`
		} `json:"messages"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}
	out := make([]Message, 0, len(body.Messages))
	for _, m := range body.Messages {
		text := m.Text
		if text == "" {
			text = m.Message
		}
		direction := strings.ToLower(m.Boundness)
		if direction == "" {
			direction = strings.ToLower(m.Direction)
		}
		if strings.Contains(direction, "in") {
			direction = "received"
		} else if strings.Contains(direction, "out") {
			direction = "sent"
		}
		out = append(out, Message{m.ID, text, direction, m.CreatedAt})
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].CreatedAt < out[j].CreatedAt })
	return out, nil
}
