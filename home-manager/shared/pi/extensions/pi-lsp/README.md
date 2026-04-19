# pi-lsp

LSP extension for pi with eager session-start warmup for likely workspace servers.

Supported languages:
- TypeScript
- Nix
- Kotlin

All dedicated semantic tools (`workspace_symbols`, `document_symbols`, `definition`, `references`, `hover`, `diagnostics`) support Kotlin through the configured `kotlin-lsp` server.

Semantic tools exposed to the agent:
- `lsp_query` - compatibility umbrella tool
- `workspace_symbols`
- `document_symbols`
- `definition`
- `references`
- `hover`
- `diagnostics`

Interactive commands:
- `/lsp-status` - show configured and currently tracked language server runtimes
- `/lsp-restart` - restart all tracked language server runtimes
- `/lsp-stop` - stop all tracked language server runtimes
- `/lsp-log` - show recent lifecycle and stderr log lines

Capability notes:
- some language servers do not implement every LSP method
- when `workspace/symbol` is unsupported, the extension degrades gracefully and suggests `grep`, `document_symbols`, `definition`, or `references`
- when semantic requests are unavailable, the extension returns degraded fallback guidance instead of a dead-end failure where practical

This extension is intentionally conservative:
- it does not hook write/edit tools
- it warms likely workspace servers on session start to reduce first-call latency
- it does not run semantic checks automatically after edits
- the agent must call an LSP tool explicitly when it wants semantic checks

Configuration is loaded from `~/.pi/agent/pi-lsp.json` unless `PI_LSP_CONFIG` overrides it.

Planning notes:
- `IMPROVEMENT-OVERVIEW.md` - proposed reliability and UX improvements for Kotlin and other slow-starting LSPs
- `IMPLEMENTATION-PLAN.md` - concrete phased implementation plan for warmup, lifecycle state, Kotlin root detection, and debuggability
