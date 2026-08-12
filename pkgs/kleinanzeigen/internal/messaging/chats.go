package messaging

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/url"

	"github.com/befrvnk/nixos-config/pkgs/kleinanzeigen/internal/auth"
)

type Chat struct {
	ID           string `json:"id"`
	Title        string `json:"title"`
	Counterparty string `json:"counterparty"`
	Preview      string `json:"preview"`
	Unread       bool   `json:"unread"`
}

func Chats() ([]Chat, error) {
	token, err := auth.Credentials()
	if err != nil {
		return nil, err
	}
	uid, err := auth.AccountID()
	if err != nil {
		return nil, err
	}
	u := "https://gateway.kleinanzeigen.de/messagebox/api/users/" + url.PathEscape(uid) + "/conversations?page=0&size=100"
	r, err := http.NewRequest(http.MethodGet, u, nil)
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
		return nil, fmt.Errorf("chats request returned %s", resp.Status)
	}
	var body struct {
		Conversations []struct {
			ID         string `json:"id"`
			AdTitle    string `json:"adTitle"`
			BuyerName  string `json:"buyerName"`
			SellerName string `json:"sellerName"`
			Text       string `json:"textShortTrimmed"`
			Unread     bool   `json:"unread"`
		} `json:"conversations"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}
	out := make([]Chat, 0, len(body.Conversations))
	for _, c := range body.Conversations {
		name := c.SellerName
		if name == "" {
			name = c.BuyerName
		}
		out = append(out, Chat{c.ID, c.AdTitle, name, c.Text, c.Unread})
	}
	return out, nil
}
