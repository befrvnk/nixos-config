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
- Agent bash tool calls show both the original command and the rewritten `nix shell ...` command for transparency.
- The parser is intentionally conservative and targets common shell command patterns.
