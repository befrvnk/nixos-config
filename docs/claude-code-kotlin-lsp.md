# Claude Code Kotlin LSP Setup

Kotlin language server integration for Claude Code, managed fully by Nix.
Works on both Darwin (macbook) and NixOS (framework) via `home-manager/shared/claude-code/`.

## How It Works

Claude Code supports LSP servers through plugins. The official `kotlin-lsp` plugin
from the `claude-plugins-official` marketplace wraps JetBrains' Kotlin Language Server.

The Nix setup:
1. Installs `pkgs.kotlin-lsp` binary (GC-safe, always current version)
2. Creates a local plugin at `~/.claude/plugins/kotlin-lsp/` with the correct config
3. Registers it in `~/.claude/plugins/installed_plugins.json` via an activation script
4. Sets `ENABLE_LSP_TOOL=1` and `enabledPlugins` in `~/.claude/settings.json`

## Key Files

| File | Purpose |
|------|---------|
| `home-manager/shared/claude-code/default.nix` | Main config: plugin files, activation script, settings |
| `~/.claude/plugins/kotlin-lsp/.claude-plugin/plugin.json` | Plugin manifest with `lspServers` config |
| `~/.claude/plugins/kotlin-lsp/.lsp.json` | LSP server config (read by Claude Code) |
| `~/.claude/plugins/installed_plugins.json` | Plugin registry (updated by activation script) |
| `~/.claude/settings.json` | `ENABLE_LSP_TOOL` + `enabledPlugins` (managed by Nix) |

## Why the Activation Script

`installed_plugins.json` is a mutable file managed by Claude Code. If you install
a plugin via `claude plugin install`, it gets written pointing to a cached marketplace
path — which may reference a Nix store path that gets GC'd.

The `home.activation.registerKotlinLsp` script runs after every `nh darwin switch .`
or `rebuild switch` and rewrites the registry entry to always point to
`~/.claude/plugins/kotlin-lsp` (the Nix-managed path):

```nix
activation.registerKotlinLsp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  ${pkgs.jq}/bin/jq --arg id "..." --arg path "..." '
    .plugins[$id] = [{ "installPath": $path, ... }]
  ' "$pluginsFile" > "$tmpFile" && mv "$tmpFile" "$pluginsFile"
'';
```

## Plugin ID Convention

The plugin uses the key `kotlin-lsp@claude-plugins-official` in both
`installed_plugins.json` and `enabledPlugins` in settings. This matches what
`claude plugin install kotlin-lsp` would use, preventing Claude Code from
prompting to reinstall on startup.

## Gotchas

### ENABLE_LSP_TOOL is required
Without `env.ENABLE_LSP_TOOL = "1"` in settings, the LSP tool is never activated
even if the plugin is installed and the binary works.

### Plugin must be in installed_plugins.json
Claude Code does **not** scan `~/.claude/plugins/*/` for unregistered plugins.
A plugin only works if it appears in `installed_plugins.json`. This is why the
activation script is needed — Nix can manage the plugin files but not this
mutable registry.

### Keys must match across all three locations
The plugin identifier must be consistent in:
1. `installed_plugins.json` → key under `.plugins`
2. `settings.json` → key under `enabledPlugins`
3. The `plugin.json` manifest `name` field (just `kotlin-lsp`, without the marketplace suffix)

### args: ["--stdio"] is required
The `kotlin-lsp` binary communicates over stdio. Without `args = [ "--stdio" ]` in
both `plugin.json lspServers` and `.lsp.json`, the server won't start.

### LSP needs a Gradle project to give meaningful results
A standalone `.kt` file in `/tmp` may work for basic type hover, but the Kotlin
LSP initializes fully only when given a proper Gradle project. Claude can often
infer types from code without LSP — to verify LSP is actually active, look for
an `lsp_hover` tool call in Claude's output when asking about types.

## Verifying the Setup

After rebuild and Claude Code restart:

1. Open `/plugin` menu — `kotlin-lsp` should appear under **Installed**
2. Open a `.kt` file inside a Gradle project (`build.gradle.kts` must exist)
3. Ask Claude: "What is the exact type of `<variable>`?"
4. If LSP is active, the response uses an `lsp_hover` tool call rather than
   inferring from source code

## Platform Notes

The `shared/claude-code/` module is imported by both hosts:
- **Darwin**: `home-manager/darwin/frank.nix`
- **NixOS**: `home-manager/nixos/frank.nix`

No platform-specific changes are needed — `pkgs.kotlin-lsp` is available on
both `x86_64-linux` and `aarch64-darwin`.
