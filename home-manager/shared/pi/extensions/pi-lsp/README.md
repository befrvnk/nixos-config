# pi-lsp

On-demand LSP extension for pi.

Supported languages:
- TypeScript
- Nix
- Kotlin
- Java

Semantic tools exposed to the agent:
- `lsp_query` - compatibility umbrella tool
- `workspace_symbols`
- `document_symbols`
- `definition`
- `references`
- `hover`
- `diagnostics`

Interactive commands:
- `/lsp-status` - show configured and currently running language servers
- `/lsp-restart` - stop all running servers; they restart lazily on next use

Capability notes:
- some language servers do not implement every LSP method
- when `workspace/symbol` is unsupported, the extension degrades gracefully and suggests `grep`, `document_symbols`, `definition`, or `references`

This extension is intentionally passive:
- it does not hook write/edit tools
- it does not run automatically after edits
- the agent must call an LSP tool explicitly when it wants semantic checks

Configuration is loaded from `~/.pi/agent/pi-lsp.json` unless `PI_LSP_CONFIG` overrides it.
