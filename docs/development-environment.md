# Development Environment with devenv

This repository uses **devenv** to provide a declarative, reproducible development environment with automatic shell activation, git hooks, and Claude Code integration.

## Overview

The development environment provides:
- ✅ **Automatic shell activation** via direnv when entering the directory
- ✅ **Automatic code formatting** with nixfmt on commit
- ✅ **Claude Code integration** with custom commands and hooks
- ✅ **Project-specific tools** (git, nixfmt, statix, deadnix, nh)
- ✅ **MCP servers** (Context7, devenv)
- ✅ **Custom scripts** (rebuild, sysinfo, generations)

## Quick Start

### First Time Setup

1. **Rebuild your system** to install devenv:
   ```bash
   sudo nixos-rebuild switch --flake .#framework
   ```

2. **Approve the environment** (security measure):
   ```bash
   cd ~/nixos-config
   direnv allow
   ```

3. **Done!** The environment will automatically activate whenever you enter the directory.

### Daily Usage

Just `cd` into the repository - everything else is automatic:

```bash
cd ~/nixos-config
# Environment automatically loads with all tools and configurations

# Edit files normally
vim devenv.nix

# Commit changes - formatting happens automatically
git commit -m "feat: add new feature"

# Use custom commands
rebuild switch    # Rebuild NixOS
sysinfo          # Show system information
generations      # List NixOS generations
```

## How It Works

### devenv + direnv Integration

1. **devenv** (`devenv.nix`) defines the development environment:
   - Packages available in the shell
   - Git hooks configuration
   - Claude Code integration
   - Custom scripts and commands
   - Environment variables

2. **direnv** (`.envrc`) automatically loads the environment:
   - Watches `.envrc` and `devenv.nix` for changes
   - Caches the environment for instant activation
   - Loads/unloads when entering/leaving the directory

3. **Result**: No manual `nix develop` or `devenv shell` commands needed!

### Automatic Code Formatting

Pre-commit hooks automatically format Nix files:

1. When you run `git commit`, the hook intercepts it
2. Formats all staged `.nix` files with `nixfmt-rfc-style`
3. Re-stages the formatted files
4. Proceeds with the commit

**Note**: You can also use the `/format` slash command in Claude Code to format files manually.

### Claude Code Integration

The devenv configuration provides:

**Custom Slash Commands** (in Claude Code):
- `/rebuild` - Rebuild and switch NixOS configuration
- `/boot` - Rebuild and activate on next boot
- `/test` - Test configuration without persisting
- `/update` - Update flake inputs
- `/check` - Check flake for errors
- `/format` - Format Nix files
- `/lint` - Lint with statix
- `/gc` - Run garbage collection

**Workflow Hooks**:
- **Protect secrets**: Blocks editing of `.env`, `.secret`, `.key`, `.pem` files
- **Nix file notifications**: Shows reminder to rebuild after editing `.nix` files
- **Auto-formatting**: Runs nixfmt after Claude Code edits files

**MCP Servers**:
- **Context7**: Documentation and code examples for libraries
- **devenv**: Devenv-specific context and capabilities

**Custom Agents**:
- Agents are defined in `.claude/agents/*.md`
- Available agents: Plan, Code, Code-Quick, Commit, Debug, Docs, Investigate, Test
- Invoke with `@agent-name` (e.g., `@Plan`, `@Code`)

## Configuration Files

### devenv.yaml

Defines Nix inputs for the environment:

```yaml
inputs:
  nixpkgs:
    url: github:NixOS/nixpkgs/nixpkgs-unstable

allowUnfree: true
```

**To update inputs**: Run `devenv update`

### devenv.nix

Main configuration file defining the environment. Key sections:

**Packages**:
```nix
packages = with pkgs; [
  git
  nixfmt-rfc-style
  statix
  deadnix
  nh
];
```

**Git Hooks**:
```nix
git-hooks.hooks = {
  nixfmt = {
    enable = true;
    package = pkgs.nixfmt-rfc-style;
  };
};
```

**Scripts**:
```nix
scripts = {
  rebuild.exec = ''...'';
  sysinfo.exec = ''...'';
  generations.exec = ''...'';
};
```

**Claude Code**:
```nix
claude.code = {
  enable = true;
  commands = { ... };
  hooks = { ... };
  mcpServers = { ... };
};
```

### .envrc

Tells direnv to use devenv:

```bash
#!/usr/bin/env bash
eval "$(devenv direnvrc)"
use devenv
```

**Note**: This file is gitignored if it contains local overrides. The default version is version-controlled.

## Available Tools & Commands

### Shell Commands

When in the devenv environment, these commands are available:

```bash
# NixOS rebuild helpers
rebuild          # Boot mode (default)
rebuild switch   # Switch immediately

# System info
sysinfo          # Show system info and current generation
generations      # List all NixOS generations

# Development tools
nixfmt           # Format Nix code
statix           # Lint Nix code
deadnix          # Find dead Nix code
nh               # Nix helper (better rebuild experience)
```

### devenv CLI Commands

```bash
# Environment management
devenv shell          # Enter the environment manually
devenv info          # Show environment information
devenv update        # Update devenv.lock

# Search and discovery
devenv search <pkg>  # Search for packages

# Cleanup
devenv gc            # Delete old shell generations
```

### Claude Code Slash Commands

See "Claude Code Integration" section above.

## Workflow Integration

### With VS Code / Editors

The environment activates automatically when you `cd` into the directory from an integrated terminal. Your editor will have access to all tools.

### With Claude Code

1. **Automatic activation**: Claude Code runs commands in the devenv environment
2. **Slash commands**: Use `/rebuild`, `/check`, etc. for common operations
3. **Git hooks**: Formatting happens automatically on Claude's edits
4. **Workflow protection**: Hooks prevent editing sensitive files

### With Git

All git operations work normally:
- Pre-commit hooks run automatically
- Formatted code is committed
- No manual formatting needed

## Customization

### Adding Packages

Edit `devenv.nix` and add to the `packages` list:

```nix
packages = with pkgs; [
  git
  nixfmt-rfc-style
  your-package-here  # Add here
];
```

Then reload: `cd .. && cd -` or wait for direnv to detect the change.

### Adding Git Hooks

Edit the `git-hooks.hooks` section in `devenv.nix`:

```nix
git-hooks.hooks = {
  nixfmt = { enable = true; package = pkgs.nixfmt-rfc-style; };
  statix.enable = true;     # Add linter
  deadnix.enable = true;    # Add dead code detector
};
```

### Adding Scripts

Add to the `scripts` section in `devenv.nix`:

```nix
scripts = {
  my-script.exec = ''
    echo "Your bash script here"
  '';
};
```

Scripts become available as commands in the shell.

### Adding Claude Code Commands

Add to the `claude.code.commands` section in `devenv.nix`:

```nix
claude.code.commands = {
  my-command = ''
    Description of what this does

    ```bash
    command-to-run
    ```
  '';
};
```

## Troubleshooting

### "direnv: error .envrc is blocked"

Run `direnv allow` in the repository directory. This is a security feature.

### Environment not activating

1. Check direnv is installed: `type direnv`
2. Check direnv is hooked into your shell (should be automatic after rebuild)
3. Try manually: `direnv allow`

### Pre-commit hook not running

Ensure you've entered the repository at least once after installing devenv. The hook installs automatically when the environment loads.

### Changes to devenv.nix not applying

Exit and re-enter the directory:
```bash
cd .. && cd nixos-config
```

Or reload direnv manually:
```bash
direnv reload
```

### devenv.lock out of sync

Update the lock file:
```bash
devenv update
```

## Comparison with Previous Setup

### Before (Nix Flake devShell)

```bash
# Manual activation required
nix develop

# Or automatic with direnv
# .envrc: use flake

# Git hooks via pre-commit-hooks.nix in flake.nix
# No Claude Code integration
# No custom scripts
```

### After (devenv)

```bash
# Automatic activation via direnv
# Just cd into directory

# Same git hooks, better organized
# Claude Code integration built-in
# Custom scripts and commands
# MCP server configuration
# More declarative and composable
```

### Key Improvements

1. **Better organization**: All dev environment config in `devenv.nix`
2. **Claude Code integration**: Slash commands, hooks, MCP servers
3. **Custom scripts**: Project-specific commands available in PATH
4. **Cleaner flake.nix**: Removed dev shell and pre-commit-hooks input
5. **Composability**: Easier to add new tools and configurations

## Benefits

- ✅ **Zero manual setup** - Everything configured declaratively
- ✅ **Consistent environment** - Same tools for all contributors
- ✅ **Automatic operation** - Works transparently in the background
- ✅ **Fast loading** - Cached by direnv for instant activation
- ✅ **Project-specific** - Only affects this repository
- ✅ **Reproducible** - Same environment every time
- ✅ **Claude Code ready** - Integrated AI coding assistance

## Technical Details

### File Locations

- **devenv config**: `devenv.nix`, `devenv.yaml`
- **direnv config**: `home-manager/direnv.nix` (system-level)
- **direnv trigger**: `.envrc` (in repository root)
- **Git hooks**: Installed to `.git/hooks/` automatically
- **Generated files**: `.devenv/`, `devenv.lock`, `.mcp.json`
- **Claude Code config**: `.claude/commands/`, `.claude/agents/`, `.claude/settings.json`

### Generated Files

devenv generates these files (gitignored):
- `.devenv/` - Built environment and shell
- `devenv.lock` - Lock file for reproducible builds
- `.mcp.json` - MCP server configuration for Claude Code
- `.claude/commands/*.md` - Slash command definitions (symlinks to nix store)
- `.claude/settings.json` - Claude Code settings (symlink to nix store)

### Integration with NixOS

The devenv package is installed via `home-manager/packages.nix`, making it available system-wide. The project-specific configuration (`devenv.nix`) is only active when in this directory.

### Why devenv?

1. **Claude Code integration**: Native support for custom commands, hooks, and MCP servers
2. **Better DX**: More intuitive than raw Nix flakes for development environments
3. **Composability**: Easy to add services, languages, tools
4. **Project-focused**: Designed for development environments specifically
5. **Active development**: Well-maintained with growing ecosystem

## Related Files

- `devenv.nix` - Main development environment configuration
- `devenv.yaml` - Input configuration (like flake inputs)
- `.envrc` - direnv trigger file
- `home-manager/direnv.nix` - System-level direnv configuration
- `home-manager/packages.nix:9` - devenv package installation
- `modules/system/core.nix:27-30` - Trusted users for cachix
- `.claude/agents/*.md` - Claude Code agent definitions

## Further Reading

- [devenv Documentation](https://devenv.sh/)
- [devenv Claude Code Integration](https://devenv.sh/integrations/claude-code/)
- [direnv Documentation](https://direnv.net/)
- [Nix Flakes](https://nixos.wiki/wiki/Flakes)
