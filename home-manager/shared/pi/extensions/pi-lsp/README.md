# pi-lsp

On-demand LSP extension for pi.

Supported languages:
- TypeScript
- Nix
- Kotlin
- Java

This extension is intentionally passive:
- it does not hook write/edit tools
- it does not run automatically after edits
- the agent must call `lsp_query` explicitly when it wants semantic checks
