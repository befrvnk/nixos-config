# Copilot live models Pi extension

This extension replaces Pi's static `github-copilot` model catalog during Pi's model refresh with the authenticated GitHub Copilot `/models` catalog.

It specifically sends:

```http
X-GitHub-Api-Version: 2026-06-01
Copilot-Integration-Id: vscode-chat
```

That API version is required for Copilot Enterprise to expose full context metadata, including the long-context limits (`922k` prompt tokens + `128k` output tokens).

## Runtime behavior

- Registers Pi's dynamic provider `refreshModels` callback for the built-in `github-copilot` provider.
- Restores Copilot's IDE identity headers at provider scope because refreshed models replace Pi's header-bearing built-in model definitions.
- Restores missing `session_id` and `x-client-request-id` routing headers on standalone Copilot requests such as compaction summaries without enabling prompt-cache writes.
- Uses the canonical OAuth credential supplied by Pi after Pi has refreshed it; the extension does not read or update `auth.json`.
- Fetches `${apiBaseUrl}/models` using credential endpoint metadata, the endpoint embedded in the Copilot token, or Pi-compatible Enterprise/individual fallbacks.
- Assigns that account-specific API endpoint to every refreshed model so Enterprise inference requests do not fall back to Pi's Individual endpoint.
- Maps live models into Pi provider model configs, including endpoint/API type, reasoning levels, vision support, token pricing, and context/output limits.
- Uses Copilot's advertised full context window so Pi exposes long-context models at their actual capacity (for example, `1.05M` for GPT-5.5/5.6 models).
- Sets Pi `contextWindow` directly from `max_context_window_tokens`. If that field is absent, it reconstructs the window from the largest prompt tier plus `max_output_tokens`, falling back to the current `compaction.reserveTokens` when no output limit is available.
- Honors Pi's model-refresh cancellation signal and offline mode.
- Fails open: a failed refresh leaves Pi's previous or built-in Copilot catalog in place.
- Uses a 10-second fetch timeout by default (`PI_COPILOT_LIVE_MODELS_TIMEOUT_MS`).
- Does not write `models.json` or manage OAuth token refresh itself.

The extension intentionally does not use Pi's provider-scoped model store. The built-in Copilot provider and Pi's remote catalog already share that store; writing the account-specific live catalog there would overwrite the built-in provider's cache.

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

Run the extension suite directly; no Nix rebuild or Pi session is required:

```sh
./scripts/test-pi-extensions.sh
```

The default test run skips the live-network smoke test.

## Live smoke test

To test the real Pi auth file and Copilot Enterprise `/models` endpoint without starting a Pi chat session:

```sh
PI_COPILOT_LIVE_MODELS_LIVE_TEST=1 \
  node --test home-manager/shared/pi/extensions/copilot-live-models/live-smoke.test.ts
```

This does not print tokens. It asserts that the discovered `gpt-5.5` and `gpt-5.6-terra` models are mapped as `openai-responses` with their full `1.05M` context windows.

## Migration from the pre-0.80.9 wrapper

The previous implementation generated a `github-copilot` provider in `~/.pi/agent/models.json` before every Pi launch. Home Manager removes that provider during activation when its name matches the generated `GitHub Copilot (live catalog)` marker. Unrelated providers and top-level configuration are preserved; an otherwise empty generated file is deleted.
