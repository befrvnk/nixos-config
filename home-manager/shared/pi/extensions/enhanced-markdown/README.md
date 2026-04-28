# Enhanced Markdown

Improves pi's built-in terminal Markdown rendering for fenced code blocks.

- Replaces raw-looking triple-backtick fences with a compact bordered block.
- Keeps the fence language in the block header.
- Preserves syntax highlighting through pi's existing Markdown theme.
- Adds common language aliases such as `kt`/`kts` -> `kotlin`, `ts` -> `typescript`, and `sh`/`shell`/`zsh` -> `bash`.
- Treats `text`/`txt`/`plain`/`plaintext` as plain code while still formatting the block.
