# MacBook Darwin Setup Guide

This guide covers setting up nix-darwin with home-manager on a MacBook Pro (M4 Pro).

## Overview

The darwin configuration provides:
- **nix-darwin** for macOS system configuration
- **home-manager** for user-level configuration (shell, tools, apps)
- **Homebrew** for GUI apps not available in nixpkgs (Android Studio)
- Shared dotfiles and tooling with the Framework laptop (NixOS)

## Prerequisites

- macOS Sonoma or later
- Admin access to install software

## Installation Steps

### 1. Install Nix (Determinate Systems Installer)

The Determinate Systems installer is recommended for macOS:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

After installation, restart your terminal or source the nix profile:

```bash
. '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
```

### 2. Install Homebrew

Homebrew is used for GUI apps that aren't available in nixpkgs:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Add Homebrew to your PATH (for Apple Silicon):

```bash
eval "$(/opt/homebrew/bin/brew shellenv)"
```

### 3. Clone the Configuration Repository

```bash
git clone https://github.com/yourusername/nixos-config ~/nixos-config
cd ~/nixos-config
```

### 4. Initial nix-darwin Setup

Bootstrap nix-darwin and apply the configuration:

```bash
# First run: bootstrap nix-darwin
nix run nix-darwin -- switch --flake .#macbook

# Subsequent runs: use darwin-rebuild
darwin-rebuild switch --flake .#macbook
```

### 5. Set Default Shell (Optional)

To use Nushell as your default shell:

```bash
# Add nushell to allowed shells
echo "/run/current-system/sw/bin/nu" | sudo tee -a /etc/shells

# Change default shell
chsh -s /run/current-system/sw/bin/nu
```

## Daily Usage

### Rebuilding Configuration

After making changes to the configuration:

```bash
cd ~/nixos-config
darwin-rebuild switch --flake .#macbook
```

### Updating Flake Inputs

To update all dependencies:

```bash
cd ~/nixos-config
nix flake update
darwin-rebuild switch --flake .#macbook
```

### Managing Homebrew

Homebrew casks are declaratively managed in `hosts/macbook-darwin/default.nix`.

To add a new cask:
1. Add the cask name to the `homebrew.casks` list
2. Run `darwin-rebuild switch --flake .#macbook`

Manual Homebrew commands are not needed (cleanup is automatic).

## What's Included

### From nixpkgs (via home-manager)

CLI tools that work cross-platform:
- **Shell**: Nushell, Starship prompt, Atuin history
- **Development**: Helix, Zed, Claude Code, git, gh, lazygit, jujutsu
- **Utilities**: bat, eza, fd, fzf, htop, yazi, navi

### From Homebrew

GUI apps configured via nix-darwin:
- Android Studio (native ARM64 macOS build)

### macOS System Defaults

Configured via nix-darwin:
- Dock: autohide, no recent apps, smaller icons
- Finder: show extensions, path bar, status bar
- Keyboard: fast key repeat, no auto-capitalization
- Trackpad: tap to click, right-click enabled
- Security: Touch ID for sudo

## Configuration Structure

```
nixos-config/
├── flake.nix                          # Entry point
├── lib/darwin.nix                     # Darwin host builder
├── hosts/macbook-darwin/
│   └── default.nix                    # macOS system config
└── home-manager/
    ├── darwin/                        # Darwin-specific configs
    │   ├── frank.nix                  # Entry point (imports shared + darwin)
    │   ├── ghostty.nix                # macOS Ghostty (no Stylix)
    │   ├── nushell.nix                # macOS Nushell (static theme)
    │   └── packages.nix               # Darwin packages
    ├── nixos/                         # NixOS-specific configs
    │   ├── frank.nix                  # Entry point (imports shared + nixos)
    │   ├── niri/                      # Wayland compositor
    │   ├── ironbar/                   # Status bar
    │   └── ...                        # Linux-only modules
    └── shared/                        # Cross-platform modules
        ├── git.nix
        ├── ssh.nix
        ├── starship.nix
        ├── claude-code/
        └── ...
```

## Differences from NixOS (Framework)

| Feature | NixOS (Framework) | Darwin (MacBook) |
|---------|-------------------|------------------|
| Theme switching | Stylix + darkman | System appearance |
| Window manager | Niri (Wayland) | Native macOS |
| Status bar | Ironbar | Native macOS |
| Notifications | Dunst | Native macOS |
| Package manager | Nix only | Nix + Homebrew |

## Troubleshooting

### "error: file 'darwin' was not found"

Run the bootstrap command instead of darwin-rebuild:

```bash
nix run nix-darwin -- switch --flake .#macbook
```

### Homebrew permissions

If Homebrew operations fail:

```bash
sudo chown -R $(whoami) /opt/homebrew
```

### Nix daemon not running

```bash
sudo launchctl load /Library/LaunchDaemons/org.nixos.nix-daemon.plist
```

### Reset to defaults

To completely reset and start fresh:

```bash
# Remove nix-darwin
sudo rm -rf /run/current-system
sudo rm -rf /nix/var/nix/profiles/system*

# Re-bootstrap
nix run nix-darwin -- switch --flake .#macbook
```
