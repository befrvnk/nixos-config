# Nix Shell Fallback

Wraps selected bash commands in `nix shell` when the executable is not already available on `PATH`.

It applies to both:

- agent `bash` tool calls
- user `!command`

## How it works

For known commands, the extension checks whether the executable is already available locally.
If it is missing, the original command is rewritten to:

```sh
nix shell nixpkgs#<package> --command bash -lc '<original command>'
```

If a command still fails with `command not found`, the extension retries with any newly detected mapped package.
This helps with nested cases like shell wrappers or helper commands discovered only at runtime, even when the first run was not statically rewritten.

## Default command map

- `python`, `python3`, `pip`, `pip3` → `python3`
- `node`, `npm`, `npx`, `corepack`, `pnpm`, `yarn` → `nodejs`
- `jq` → `jq`
- `rg` → `ripgrep`
- `fd` → `fd`
- `shellcheck` → `shellcheck`
- `shfmt` → `shfmt`
- `uv` → `uv`
- `bun` → `bun`
- `go` → `go`
- `cargo`, `rustc` → Rust packages
- `yq` → `yq-go`

## Notes

- Commands already available on `PATH` are left untouched.
- Existing `nix shell`, `nix develop`, and `nix run` invocations are left untouched.
- The parser now handles additional patterns like background jobs, `xargs`, `find -exec`, and nested `sh -c`/`bash -lc` command strings.
- Agent bash tool calls show both the original command and the rewritten `nix shell ...` command for transparency.
- The parser is intentionally conservative and targets common shell command patterns.
