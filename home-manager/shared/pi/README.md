# Pi extension suite

This directory contains the cross-platform Pi configuration and ten local extensions:

- `answer`
- `bash-output-control`
- `copilot-live-models`
- `enhanced-markdown`
- `nav-tools`
- `pi-lsp`
- `read-path-ui`
- `search-tools`
- `subagents`
- `system-theme-sync`

## Deployment

Home Manager deploys each extension to `~/.pi/agent/extensions/<name>` for normal auto-discovery and `/reload` support. `package.json` also describes the source tree as one local Pi package for development and smoke testing; it does not replace the Home Manager deployment.

Pi-provided libraries use `"*"` peer dependencies and are not installed or bundled. Extensions prefer Node built-ins, so the Nix deployment requires no npm installation.

## Lifecycle conventions

Extension factories register bounded behavior only. Timers, language servers, and prototype patches start during `session_start` or lazily and are released idempotently during `session_shutdown`. Prototype patches must be owner-aware and reversible. Display-only records use custom session entries, while only information intended for the model uses custom messages. Terminal components and overlays require `ctx.mode === "tui"`.

## Tests

```sh
./scripts/test-pi-extensions.sh
./scripts/smoke-test-pi-package.sh
nix build .#checks.aarch64-darwin.pi-extension-tests --accept-flake-config
nix build .#checks.aarch64-darwin.pi-package-smoke --accept-flake-config
```

The unit check runs tests serially. The smoke check loads every entry point through the pinned Pi binary in offline RPC mode and verifies representative command registrations.
