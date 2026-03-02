# Claude Code LSP Setup

Language server integrations for Claude Code, managed fully by Nix.
Works on both Darwin (macbook) and NixOS (framework) via `home-manager/shared/claude-code/`.

## Configured LSP Servers

| Language | Package | Plugin ID | Scope |
|----------|---------|-----------|-------|
| Kotlin | `pkgs.kotlin-lsp` | `kotlin-lsp@local` | User (all projects) |
| Nix | `pkgs.nil` | `nix-lsp@local` | User (all projects) |

## Architecture

Both LSPs use a single local directory marketplace registered via `extraKnownMarketplaces`.

```
~/.claude/plugins/marketplaces/local/
├── .claude-plugin/
│   └── marketplace.json          # Lists all plugins with inline lspServers
└── plugins/
    ├── kotlin-lsp/
    │   └── README.md             # Directory must exist; config is in marketplace.json
    └── nix-lsp/
        └── README.md
```

The marketplace is registered in `~/.claude/settings.json` as:
```json
{
  "extraKnownMarketplaces": {
    "local": {
      "source": {
        "source": "directory",
        "path": "/Users/frank/.claude/plugins/marketplaces/local"
      }
    }
  }
}
```

## Key Files

| File | Purpose |
|------|---------|
| `home-manager/shared/claude-code/default.nix` | Main config: marketplace files, activation script, settings |
| `~/.claude/plugins/marketplaces/local/.claude-plugin/marketplace.json` | Plugin catalog with inline `lspServers` |
| `~/.claude/plugins/installed_plugins.json` | Plugin registry (written declaratively by activation script) |
| `~/.claude/settings.json` | `ENABLE_LSP_TOOL` + `enabledPlugins` + `extraKnownMarketplaces` |

## Activation Script

`home.activation.registerLspPlugins` writes `installed_plugins.json` **declaratively**
(full replacement, not merge) on every rebuild. Adding or removing a plugin from the
Nix config automatically reflects in the registry after the next rebuild.

## Gotchas

### ENABLE_LSP_TOOL is required
Without `env.ENABLE_LSP_TOOL = "1"` in settings, no LSP tools activate.

### Plugin must be in installed_plugins.json
Claude Code does **not** scan plugin directories automatically. A plugin only loads
if it appears in `installed_plugins.json`.

### extraKnownMarketplaces format is strict
The value must be a nested object — `{ "source": { "source": "directory", "path": "..." } }`.
A plain string path causes Claude Code to fail silently on startup.

### marketplace.json requires owner and author fields
Top-level `owner: { name: "..." }` is required or the file fails to parse.
Each plugin entry needs `author: { name: "..." }` as well.

### Plugin source directories must exist on disk
The `source` path in marketplace.json (e.g. `./plugins/kotlin-lsp`) must be a real
directory. A `README.md` inside is sufficient to satisfy this check.

### @marketplace suffix must reference a real marketplace
Claude Code validates plugin IDs against known marketplaces before loading.
Using `@claude-plugins-official` for a plugin not in that registry fails.
Using `@local` requires `local` to be registered via `extraKnownMarketplaces`.

### Orphaned cache markers
When plugin IDs change between rebuilds, Claude Code writes `.orphaned_at` in the
cache dir. The activation script clears these to prevent broken state.

### Project .lsp.json does NOT work
`.claude/.lsp.json` in the project root is not read by Claude Code. Only `.lsp.json`
files inside registered plugin directories are loaded. This file is gitignored.

## Verifying the Setup

After rebuild and Claude Code restart:

1. Open `/plugin` menu — both `kotlin-lsp` and `nix-lsp` should appear under **Installed**
2. Open a `.nix` file and ask Claude about a variable type — LSP hover should activate
3. Open a `.kt` file and ask Claude about a symbol type — Kotlin LSP should activate

## Platform Notes

The `shared/claude-code/` module is imported by both hosts:
- **Darwin**: `home-manager/darwin/frank.nix`
- **NixOS**: `home-manager/nixos/frank.nix`

`pkgs.nil` and `pkgs.kotlin-lsp` are available on both `x86_64-linux` and `aarch64-darwin`.
