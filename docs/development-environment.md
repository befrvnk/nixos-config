# Development Environment

This repo uses **devenv** with **direnv** for a reproducible project shell.

## What It Provides

- automatic shell activation via `direnv`
- git hooks on commit
- Claude Code slash commands and hooks
- repo-local helper commands like `rebuild`, `clean`, and `flake-update`
- linting and packaging tools such as `nixfmt`, `statix`, `shellcheck`, `deadnix`, and `nurl`

## First-Time Setup

```bash
cd ~/nixos-config
direnv allow
```

If you have not installed the system config yet, apply it first with:

### NixOS
```bash
rebuild switch
# or
nh os switch .
```

### Darwin
```bash
nh darwin switch .
```

## Daily Usage

Just enter the repository:

```bash
cd ~/nixos-config
```

The shell activates automatically.

## Available Commands

### General
```bash
clean [N]                 # Keep the last N generations (default: 5)
flake-update              # Update flake inputs and package metadata
nix fmt                   # Format Nix files
statix check .            # Lint Nix files
shellcheck scripts/*.sh   # Lint top-level helper scripts
```

### NixOS-only helpers
```bash
rebuild                   # Build for next boot
rebuild switch            # Build and switch now
sysinfo                   # Show system information
generations               # List NixOS generations
wifi-debug                # Capture WiFi debug logs
tpm-rekey                 # Re-enroll TPM unlock material
```

### Cross-platform test helper
```bash
test-pi-extensions
```

## Git Hooks

Configured in `devenv.nix`.

Current commit-time hooks:
- `nixfmt`
- `statix`

Formatting does **not** run automatically after every Claude edit. It runs on commit, or when you explicitly run `nix fmt`.

## Claude Code Integration

`devenv.nix` defines Claude Code commands and hooks.

### Slash commands
- `/rebuild`
- `/boot`
- `/test`
- `/update`
- `/check`
- `/format`
- `/lint`
- `/clean`
- `/commit`
- `/firewall` (NixOS only)

### Hooks
- `protect-secrets`
- `nix-file-edited`

## Generated / Related Files

- `devenv.nix` - main devenv config
- `devenv.yaml` - devenv input config
- `.envrc` - direnv trigger
- `devenv.lock` - devenv lock file
- `.devenv/` - generated local environment artifacts
- `.mcp.json` - generated MCP configuration

## Notes

- the git hook config is generated from `devenv.nix`
- if devenv settings change, re-enter the repo or run `direnv allow` again
- helper scripts are designed to run from inside this repo's devenv shell
