# Development Environment & Automatic Code Formatting

This repository uses **direnv** and **pre-commit hooks** to automatically format Nix code with nixfmt. Everything is fully automated—no manual commands required.

## How It Works

### Automatic Environment Loading with direnv

The repository includes a `.envrc` file that automatically loads the Nix development shell whenever you enter the directory:

1. **direnv** is configured in your home-manager configuration (`home-manager/direnv.nix`)
2. When you `cd` into `nixos-config`, direnv automatically runs `nix develop`
3. The development shell (`devShells.default` in `flake.nix`) loads nixfmt and installs git hooks
4. When you leave the directory, the environment is automatically unloaded

**This works in all scenarios:**
- Opening a terminal directly in the `nixos-config` directory
- Using `cd` to navigate into the directory
- Returning to the directory from a subdirectory

### Automatic Code Formatting with Git Hooks

A pre-commit hook automatically formats all Nix files before each commit:

1. When you run `git commit`, the hook intercepts it
2. It finds all staged `.nix` files
3. Formats them with `nixfmt-rfc-style`
4. Re-stages the formatted files
5. Proceeds with the commit

**Result:** All committed Nix code is guaranteed to be consistently formatted.

## Setup (First Time Only)

After rebuilding your NixOS system with the direnv configuration, you need to approve the `.envrc` file once:

```bash
cd ~/nixos-config  # or wherever you cloned the repository
direnv allow
```

That's it! From now on, everything is automatic.

## What Happens Behind the Scenes

### direnv Configuration (`home-manager/direnv.nix`)

The direnv configuration:
- Enables direnv integration with bash and zsh
- Enables nix-direnv for fast, cached shell loading
- Automatically hooks into your shell on system rebuild

### Development Shell (`flake.nix`)

The development shell includes:
- `nixfmt-rfc-style` package for code formatting
- Pre-commit hook configuration that:
  - Automatically installs hooks when the shell loads
  - Runs nixfmt on all `.nix` files before commits
  - Manages hook updates automatically

### .envrc File

Contains a single line:
```
use flake
```

This tells direnv to load the default development shell from the flake.

## Daily Usage

Once set up, you don't need to think about it:

1. **Navigate to the repository** - direnv loads automatically
2. **Make changes to Nix files** - edit as normal
3. **Commit changes** - formatting happens automatically
4. **Leave the directory** - environment unloads automatically

No manual `nix develop` commands, no manual formatting, no manual hook installation.

## Troubleshooting

### "direnv: error .envrc is blocked"

Run `direnv allow` in the repository directory. This is a security feature—you must explicitly approve .envrc files.

### Pre-commit hook not running

Ensure you've entered the repository directory at least once after setting up direnv. The hook is installed automatically when the dev shell loads.

### direnv not activating automatically

Check that direnv is properly hooked into your shell. After a system rebuild, the hook should be automatically configured. You can verify with:

```bash
type direnv
```

You should see the direnv function definition.

## Benefits

- **Zero manual setup** - Everything configured through NixOS/home-manager
- **Consistent formatting** - All Nix code follows the same style
- **Automatic operation** - Works transparently in the background
- **Fast loading** - nix-direnv caches the shell for instant activation
- **Project-specific** - Only affects this repository, not other git projects
- **Reproducible** - Anyone cloning the repo gets the same setup

## Technical Details

### File Locations

- **direnv config**: `home-manager/direnv.nix`
- **Dev shell**: `flake.nix` (devShells.${system}.default)
- **direnv trigger**: `.envrc` (in repository root)
- **Git hooks**: Installed to `.git/hooks/pre-commit` automatically

### Hook Implementation

The pre-commit hook uses `pre-commit-hooks.nix`, a Nix library that integrates with popular pre-commit frameworks. The hook:

- Runs only on staged `.nix` files (not all files)
- Automatically re-stages formatted files
- Fails the commit if nixfmt encounters errors
- Is managed by the development shell (updates automatically)

### Why This Approach?

1. **No manual installation** - Hooks install automatically via shellHook
2. **Always up to date** - Hooks update when the dev shell updates
3. **Reproducible** - Same setup for all contributors
4. **Integrated with Nix** - Uses the same nixfmt version across tools
5. **Automatic activation** - direnv removes the need to remember `nix develop`

## Related Files

- `flake.nix:83-100` - Development shell and pre-commit hook configuration
- `home-manager/direnv.nix` - direnv home-manager configuration
- `home-manager/frank.nix:8` - Import of direnv configuration
- `.envrc` - direnv activation file
