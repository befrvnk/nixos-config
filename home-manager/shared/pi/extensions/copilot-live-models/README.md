# Copilot live models Pi extension

This extension replaces Pi's static `github-copilot` model catalog at session startup with the live GitHub Copilot `/models` catalog.

It specifically sends:

```http
X-GitHub-Api-Version: 2026-06-01
Copilot-Integration-Id: vscode-chat
```

That API version is required for Copilot Enterprise to expose GPT-5.5's long-context limits (`922k` prompt tokens + `128k` output tokens).

## Runtime behavior

- Reads existing Pi GitHub Copilot OAuth credentials from `~/.pi/agent/auth.json`.
- Uses the cached Copilot token when valid, otherwise refreshes it through GitHub's Copilot token endpoint.
- Fetches `${apiBaseUrl}/models` from the token metadata, so Enterprise endpoints are discovered dynamically.
- Maps live models into Pi provider model configs.
- Sets Pi `contextWindow` from Copilot's `max_prompt_tokens + compaction.reserveTokens`, because Pi subtracts the reserve to decide when to compact.
- Calls `pi.registerProvider("github-copilot", ...)` to replace Pi's built-in static Copilot catalog for normal sessions.
- Provides `write-models-json.ts`, used by the Home Manager `pi` wrapper to refresh `~/.pi/agent/models.json` before Pi starts. This makes model discovery available even for code paths such as `pi --list-models` that do not load extensions.
- Fails open: if auth or discovery fails, Pi keeps its built-in catalog or the last successfully generated `models.json`.
- Uses a 10-second fetch timeout by default (`PI_COPILOT_LIVE_MODELS_TIMEOUT_MS`) so a hanging Copilot endpoint does not block Pi startup indefinitely.
- The Home Manager wrapper invokes the writer with `node --experimental-strip-types` to make direct `.ts` execution explicit.

## Controls

Disable the extension for one run:

```sh
PI_COPILOT_LIVE_MODELS=0 pi
```

Enable debug logging:

```sh
PI_COPILOT_LIVE_MODELS_DEBUG=1 pi
```

Override the live catalog timeout:

```sh
PI_COPILOT_LIVE_MODELS_TIMEOUT_MS=5000 pi
```

## Unit tests

Run the extension's local unit tests directly; no Nix rebuild or Pi session required:

```sh
node --test home-manager/shared/pi/extensions/copilot-live-models/*.test.ts
```

The default test run skips the live-network smoke test.

## Live smoke test

To test the real Pi auth file and Copilot Enterprise `/models` endpoint without starting a Pi chat session:

```sh
PI_COPILOT_LIVE_MODELS_LIVE_TEST=1 \
  node --test home-manager/shared/pi/extensions/copilot-live-models/live-smoke.test.ts
```

This does not print tokens. It asserts that the discovered `gpt-5.5` model is mapped as `openai-responses` with at least a 1M-token context window.

## `models.json` wrapper smoke test

To test the pre-launch `models.json` path without modifying your real Pi config:

```sh
tmpdir=$(mktemp -d)
cp ~/.pi/agent/auth.json "$tmpdir/auth.json"
printf '%s\n' '{"compaction":{"reserveTokens":128000}}' > "$tmpdir/settings.json"
PI_CODING_AGENT_DIR="$tmpdir" node --experimental-strip-types \
  home-manager/shared/pi/extensions/copilot-live-models/write-models-json.ts
PI_CODING_AGENT_DIR="$tmpdir" COPILOT_GITHUB_TOKEN=dummy pi --list-models gpt-5.5
rm -rf "$tmpdir"
```

Expected output includes `github-copilot  gpt-5.5  1.1M`.

## Pi 0.79.1 caveat

Pi 0.79.1 appears not to load extensions for `pi --list-models`. The Home Manager wrapper handles this by running `write-models-json.ts` before delegating to the real Pi binary, so `--list-models` sees a freshly generated provider config from `models.json`.
