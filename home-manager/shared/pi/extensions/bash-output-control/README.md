# bash-output-control

Overrides pi's built-in `bash` tool with a context-friendly variant:

- commands with incomplete displayed output save full stdout/stderr to a unique `pi-bash-*.log` file in the system temp directory (`os.tmpdir()`)
- the final tool output includes the full-output path only when such a file was written
- the agent can reduce displayed output with:
  - `tailLines` — keep only the last N lines after filtering
  - `maxBytes` — cap displayed bytes after tailing/filtering
  - `include` / `exclude` — line filters
  - `filterMode` — `regex` or `literal`
  - `ignoreCase` — case-insensitive filters

This is intended for noisy build/test tools such as Gradle, Maven, npm, and test runners.

Saved full-output files may contain sensitive command output. They are created only when displayed output is incomplete because lines were filtered or truncated. They are not deleted by the extension; cleanup is delegated to the operating system's normal temporary-directory retention policy. You can also remove stale files manually from the directory reported by `node -p 'require("node:os").tmpdir()'`.
