# Global Agent Context

## Nix Shell for Commands

On macOS/Darwin, assume only tools installed by default on a clean macOS system are available. For any non-standard CLI tool, use it through Nix rather than relying on Homebrew, npm globals, pip globals, or local machine state.

Use `nix shell` to make required packages available temporarily rather than asking the user to install them.

```sh
# Run a command from nixpkgs
nix shell nixpkgs#<package> --command <command> [args...]

# Example: need jq
nix shell nixpkgs#jq --command jq '.key' file.json

# Multiple packages at once
nix shell nixpkgs#ripgrep nixpkgs#fd --command rg "pattern"
```

### Guidelines

- Always use `nix shell nixpkgs#<package>` with the `--command` flag for one-off commands
- Prefer project-provided commands such as `devenv`, `nh`, or flake apps when available
- For repeated use within a task, run `nix shell nixpkgs#<package>` once to enter a subshell, then run multiple commands
- The package name in nixpkgs may differ from the command name (e.g., `nixpkgs#ripgrep` provides `rg`)
- If unsure of the nixpkgs attribute name, search with `nix search nixpkgs <query>`
- Do NOT rely on Homebrew, npm globals, pip globals, or other local user-installed tools unless explicitly requested
- Do NOT suggest the user permanently install packages unless they ask
- Do NOT use `nix-shell -p` (legacy syntax); prefer `nix shell nixpkgs#`
