# kleinanzeigen

A Go command-line client for Kleinanzeigen public listings, search, and authenticated chat reading. It is installed declaratively through this repository's Home Manager package set.

## Public commands

```sh
kleinanzeigen version
kleinanzeigen listing 'https://www.kleinanzeigen.de/s-anzeige/...'
kleinanzeigen listing --json 'https://www.kleinanzeigen.de/s-anzeige/...'
kleinanzeigen images --output ./images 'https://www.kleinanzeigen.de/s-anzeige/...'
kleinanzeigen search --query 'i:SY' --postcode 81929 --radius 50 --category 217 --max-price 3000
kleinanzeigen search --query 'i:SY' --location-id 6526 --json
```

`images` downloads only images belonging to the listing gallery; it does not collect recommendation-ad images. `search` accepts either a Kleinanzeigen numeric location ID or a postcode/place name. The default bicycle category is `217`.

## Authentication and chats

```sh
kleinanzeigen login
kleinanzeigen auth status
kleinanzeigen chats
kleinanzeigen messages '<conversation-id>'
kleinanzeigen reply '<conversation-id>' --message 'Hello' --confirm
kleinanzeigen auth logout
```

`login` uses OAuth Authorization Code + PKCE. It prints an authentication URL and requires the complete resulting callback URL to be pasted into the terminal. Credentials are never supplied by Nix and are stored outside the Nix store at:

```text
~/.config/kleinanzeigen/token.json
```

The parent directory is created with mode `0700`; the token file is written with mode `0600`. Set `KLEINANZEIGEN_TOKEN_FILE` to use a different local path.

Authenticated access tokens are refreshed automatically from the saved refresh token. `chats` and `messages` are read-only. `reply` is restricted to existing conversations, always requires `--confirm`, and reports success only after it re-reads the thread and finds an exact outbound-text match.

## Safety boundary

There is deliberately no `send` command for contacting a seller for the first time. The previously inferred conversation-creation protocol produced an apparent HTTP success without creating a visible message. A first-contact sender must not be added until its actual request flow is captured and a sent message can be verified in the resulting conversation.
