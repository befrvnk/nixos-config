# answer

Interactive `/answer` command for pi.

What it does:
- looks at the last assistant response
- extracts any questions that still need user input
- shows a compact multi-question TUI for answering them
- submits the compiled answers back into the session

Controls:
- `Tab` / `Shift+Tab` to move between questions
- `Enter` to advance
- `Shift+Enter` for a newline inside an answer
- `Esc` to cancel
- shortcut: `Ctrl+.`

The custom editor is available only in TUI mode. It propagates focus to the embedded editor for hardware-cursor and IME support, and its layout degrades safely on narrow terminals.

Notes:
- adapted from `mitsuhiko/agent-stuff`'s `pi-extensions/answer.ts`
- uses a lightweight extraction model when available, then falls back to the current model
