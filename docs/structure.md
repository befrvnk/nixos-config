# Repository Structure

This document explains the organization of this NixOS configuration.

## Top-Level Structure

```
nixos-config/
├── flake.nix           # Main flake entry point
├── flake.lock          # Flake lock file
├── lib/                # Host builder functions
├── hosts/              # Host-specific configurations
├── modules/            # System-level NixOS modules
├── home-manager/       # User-level home-manager modules
├── overlays/           # Nixpkgs overlays
├── shared/             # Cross-platform resources (themes, wallpapers)
├── scripts/            # Maintenance and update scripts
└── docs/               # Documentation
```

## Hosts Directory

Each host has its own directory:

```
hosts/
├── framework/                # NixOS (Framework laptop)
│   ├── default.nix           # Main host configuration
│   ├── hardware-configuration.nix  # Hardware-specific settings
│   └── home.nix              # Home-manager entry point
└── macbook-darwin/           # macOS (MacBook Pro M4)
    └── default.nix           # Darwin configuration + Homebrew
```

## Lib Directory

Host builder functions used by flake.nix:

```
lib/
├── hosts.nix           # mkHost (NixOS host builder)
└── darwin.nix          # mkDarwinHost (Darwin host builder)
```

## Modules Directory

System-level NixOS modules organized by category:

```
modules/
├── default.nix        # Imports all modules
├── users.nix          # User account definitions
├── desktop/           # Desktop environment
│   ├── greetd.nix     # Display manager / greeter
│   └── niri.nix       # Niri window manager (system-level)
├── hardware/          # Hardware configuration
│   ├── android.nix    # Android udev rules
│   ├── fprintd/       # Fingerprint reader
│   ├── logitech.nix   # Logitech peripherals
│   ├── nuphy.nix      # NuPhy keyboard
│   └── power-management.nix  # TLP, tuned
├── services/          # System services
│   ├── bluetooth.nix  # Bluetooth
│   ├── darkman.nix    # Dark/light mode switching (system)
│   ├── keyd.nix       # Key remapping daemon
│   ├── nextdns.nix    # DNS filtering
│   ├── oomd.nix       # Out-of-memory daemon
│   ├── pipewire.nix   # Audio server
│   ├── scx.nix        # Scheduler
│   └── udisks.nix     # Disk management
├── system/            # Core system configuration
│   ├── core.nix       # Boot, networking, locale
│   ├── packages.nix   # System packages
│   ├── security.nix   # Security settings
│   └── xkb-custom.nix # Custom keyboard layouts
└── theming/           # System theming
    └── stylix.nix     # Stylix theme configuration
```

## Home-Manager Directory

User-level modules organized by platform:

```
home-manager/
├── nixos/             # NixOS-specific modules
│   ├── frank.nix      # Main config (imports shared + NixOS modules)
│   ├── niri/          # Window manager (Wayland)
│   ├── ironbar/       # Status bar
│   ├── darkman/       # Theme switching scripts
│   ├── stylix.nix     # Theming with specializations
│   ├── nushell.nix    # Shell (Stylix theme integration)
│   └── */             # Other NixOS-specific configs
├── darwin/            # Darwin-specific modules
│   ├── frank.nix      # Main config (imports shared + darwin modules)
│   ├── ghostty.nix    # Terminal (Homebrew package)
│   ├── nushell.nix    # Shell (Nix PATH setup)
│   ├── packages.nix   # CLI packages
│   ├── zed.nix        # Zed editor
│   ├── zellij.nix     # Terminal multiplexer
│   └── zen-browser.nix # Browser with extension policies
├── shared/            # Cross-platform modules
│   ├── nushell.nix    # Shell (shared config, keybindings, carapace)
│   ├── atuin.nix      # Shell history
│   ├── git.nix        # Version control
│   ├── gh.nix         # GitHub CLI + gh-dash
│   ├── starship.nix   # Prompt
│   ├── ssh.nix        # SSH config
│   ├── claude-code/   # Claude Code configuration
│   ├── navi/          # Cheatsheet tool
│   └── */             # Other shared configs
└── mcp/               # MCP server configurations
    └── anytype.nix    # Anytype MCP server
```

## Overlays Directory

Nixpkgs overlays for custom package modifications:

```
overlays/
├── niri.nix                 # Niri package (flake version)
├── claude-code.nix          # Claude Code customizations
├── profile-sync-daemon.nix  # PSD with Zen Browser support
├── gh-enhance.nix           # GitHub enhance extension

└── */                       # Other overlays
```

## Shared Resources

Cross-platform resources:

```
shared/
└── themes.nix         # Central base16 theme definitions (Catppuccin Mocha/Latte)
```

## Scripts Directory

Maintenance and update scripts:

```
scripts/
├── show-changelogs.*   # Show changelogs after flake update
├── update-*.sh         # Package update scripts
└── take-readme-screenshots.*  # Screenshot automation
```

## Configuration Flow

1. **flake.nix** defines system configurations for both hosts
2. **lib/hosts.nix** / **lib/darwin.nix** build host configurations
3. **hosts/\*/default.nix** imports modules and hardware config
4. **modules/default.nix** imports all system modules (NixOS only)
5. **home-manager/\*/frank.nix** imports shared + platform-specific user modules

## Channel Strategy

This configuration uses `nixpkgs-unstable` as the main channel for all packages,
providing access to the latest versions while accepting slightly less stability.

## Key Concepts

- **System modules** (in `modules/`) configure system-wide settings (NixOS only)
- **Home-manager modules** (in `home-manager/`) configure user-specific settings
- **Shared modules** (in `home-manager/shared/`) work on both NixOS and Darwin
- **Overlays** modify or replace packages from nixpkgs
- **Specialisations** (via Stylix) enable theme switching without rebuilds
- **Stylix auto-theming** (`autoEnable = true`) automatically themes supported applications
