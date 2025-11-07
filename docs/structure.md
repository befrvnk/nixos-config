# Repository Structure

This document explains the organization of this NixOS configuration.

## Top-Level Structure

```
nixos-config/
├── flake.nix           # Main flake entry point
├── flake.lock          # Flake lock file
├── hosts/              # Host-specific configurations
├── modules/            # System-level NixOS modules
├── home-manager/       # User-level home-manager modules
├── overlays/           # Nixpkgs overlays
└── docs/               # Documentation
```

## Hosts Directory

Each host has its own directory with host-specific configuration:

```
hosts/
└── framework/
    ├── default.nix           # Main host configuration
    ├── hardware-configuration.nix  # Hardware-specific settings
    ├── home.nix              # Home-manager configuration
    └── overlays.nix          # Host-specific overlays
```

## Modules Directory

System-level modules are organized by category:

```
modules/
├── default.nix        # Imports all modules
├── users.nix          # User account definitions
├── desktop/           # Desktop environment configuration
│   ├── display.nix    # Display settings
│   ├── gnome.nix      # GNOME components
│   └── niri.nix       # Niri window manager
├── system/            # Core system configuration
│   ├── core.nix       # Boot, networking, locale
│   ├── packages.nix   # System packages
│   └── xkb-custom.nix # Custom keyboard layouts
├── services/          # System services
│   ├── darkman.nix    # Dark/light mode switching
│   ├── keyd.nix       # Key remapping daemon
│   └── pipewire.nix   # Audio server
└── theming/           # System theming
    └── stylix.nix     # Stylix theme configuration
```

## Home-Manager Directory

User-level modules for home-manager:

```
home-manager/
├── frank.nix          # Main user configuration (imports all modules)
├── packages.nix       # User packages
├── git.nix            # Git configuration
├── ssh.nix            # SSH configuration
├── zsh.nix            # Shell configuration
├── stylix.nix         # User-level theming
├── darkman.nix        # Dark/light mode scripts
├── niri/              # Niri-specific home configuration
├── themes.nix         # Theme definitions
└── ...                # Other application configs
```

## Overlays Directory

Nixpkgs overlays for custom package modifications:

```
overlays/
└── niri.nix           # Niri package overlay (uses flake version)
```

## Configuration Flow

1. **flake.nix** defines the system configuration for `framework` host
2. **hosts/framework/default.nix** imports all modules and hardware config
3. **modules/default.nix** imports all system modules
4. **home-manager/frank.nix** imports all user modules

## Channel Strategy

This configuration uses `nixpkgs-unstable` as the main channel for all packages,
providing access to the latest versions while accepting slightly less stability.

## Key Concepts

- **System modules** (in `modules/`) configure system-wide settings
- **Home-manager modules** (in `home-manager/`) configure user-specific settings
- **Overlays** modify or replace packages from nixpkgs
- **Specialisations** (via stylix) enable theme switching without rebuilds
