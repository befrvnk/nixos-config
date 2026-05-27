# Read Path UI

Claude Code-style grouped rendering for compact tool output.

The extension keeps normal tool behavior: file contents and fetched web content still go to the model. It only changes interactive TUI rendering so reads show paths and web fetches show URLs instead of dumping content into the terminal.

Examples:

```text
Read 2 files
⎿  home-manager/CLAUDE.md
⎿  home-manager/AGENTS.md

Web Fetch 2 URLs
⎿  https://pi.dev/
⎿  https://github.com/earendil-works/pi
```

If a read or fetch fails, expanding the tool row shows the first error line while still hiding normal successful contents.
