# Global Agent Context

## Nix Shell for Missing Commands

When a required package or command is not available in the current environment, use `nix shell` to make it available temporarily rather than asking the user to install it.

```sh
# Run a command from a package not currently installed
nix shell nixpkgs#<package> --command <command> [args...]

# Example: need jq but it's not installed
nix shell nixpkgs#jq --command jq '.key' file.json

# Multiple packages at once
nix shell nixpkgs#ripgrep nixpkgs#fd --command rg "pattern"
```

### Guidelines

- Always use `nix shell nixpkgs#<package>` with the `--command` flag for one-off commands
- For repeated use within a task, run `nix shell nixpkgs#<package>` once to enter a subshell, then run multiple commands
- The package name in nixpkgs may differ from the command name (e.g., `nixpkgs#ripgrep` provides `rg`)
- If unsure of the nixpkgs attribute name, search with `nix search nixpkgs <query>`
- Do NOT suggest the user permanently install packages unless they ask
- Do NOT use `nix-shell -p` (legacy syntax); prefer `nix shell nixpkgs#`
