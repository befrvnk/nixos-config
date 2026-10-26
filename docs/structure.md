# Repository Structure

This document explains the organization of this NixOS configuration.

## Top-Level Structure

```text
nixos-config/
├── flake.nix           # Flake inputs, host outputs and checks
├── flake.lock          # Pinned flake inputs
├── devenv.nix          # Development shell, hooks and helper commands
├── lib/                # Host builders and shared library code
├── hosts/              # Host-specific configurations
├── modules/            # System-level NixOS modules
├── home-manager/       # User-level Home Manager modules
├── overlays/           # Nixpkgs overlays for local packages
├── pkgs/               # Package definitions used by the overlays
├── shared/             # Cross-platform data (caches, themes)
├── scripts/            # Maintenance and update scripts
├── screenshots/        # README screenshots
├── docs/               # Documentation
└── .github/            # CI workflow
```

## Hosts Directory

Hosts are registered in `lib/host-inventory.nix`; the flake maps over that
inventory and builds each host with `lib/hosts.nix` or `lib/darwin.nix`.

```text
hosts/
├── framework/                # NixOS (Framework 13, Niri/Noctalia)
│   ├── default.nix           # Host-specific configuration
│   ├── hardware-configuration.nix  # Generated hardware settings
│   └── home.nix              # Home Manager entry point
├── hermi/                    # NixOS (Raspberry Pi 4, headless)
│   └── default.nix           # All-in-one configuration + OpenChamber
└── macbook-darwin/           # macOS (MacBook Pro M4)
    └── default.nix           # All-in-one configuration + Homebrew
```

## Lib Directory

Host builders and shared helpers used by `flake.nix`:

```text
lib/
├── hosts.nix              # mkHost (NixOS host builder + validation)
├── darwin.nix             # mkDarwinHost (Darwin host builder)
├── host-inventory.nix     # Host registry consumed by flake.nix
├── host-options-module.nix # my.host options, exposes hostConfig
└── overlays.nix           # Shared NixOS/Darwin overlay lists
```

## Modules Directory

System-level NixOS modules organized by category. `modules/default.nix`
imports the base and desktop profiles; each host imports `modules/` and can
add the host-specific profiles under `modules/profiles/`.

```text
modules/
├── default.nix            # Imports profiles/base.nix and profiles/desktop.nix
├── users.nix              # User account definitions
├── profiles/
│   ├── base.nix           # users, core, packages, security, xkb
│   ├── desktop.nix        # greetd, Niri, services, Stylix
│   └── framework.nix      # Framework-only hardware extras
├── desktop/
│   ├── greetd.nix         # Noctalia Greeter + greetd
│   ├── niri.nix           # Niri portals and system integration
│   ├── umbriel.nix        # Umbriel trial session
│   └── *-check.nix        # Greeter/Umbriel invariant checks
├── hardware/
│   ├── android.nix        # Android KVM group
│   ├── fprintd/           # Fingerprint reader + lid management
│   ├── keychron-m6.nix    # Keychron M6 HID/battery support
│   ├── nuphy.nix          # NuPhy WebHID udev rules
│   └── power-management.nix # tuned profiles, ABM, I/O scheduler
├── services/
│   ├── bluetooth.nix      # Bluetooth + AC auto-enable
│   ├── nextdns.nix        # systemd-resolved + NextDNS DoT
│   ├── noctalia-auth.nix  # Password-only PAM stack for the native locker
│   ├── oomd.nix           # systemd-oomd
│   ├── pipewire.nix       # PipeWire + ALSA mixer init
│   ├── scx.nix            # sched_ext scheduler
│   ├── udisks.nix         # udisks2 + exFAT
│   └── wifi-wakeup-log.nix # Suspend/resume WiFi diagnostics
├── system/
│   ├── core.nix           # Boot, networking, Nix settings, logind, GC
│   ├── packages.nix       # System packages
│   ├── security.nix       # Firewall + kernel hardening
│   └── xkb-custom.nix     # Custom keyboard layout
└── theming/
    └── stylix.nix         # System-level Stylix configuration
```

## Home-Manager Directory

User-level modules organized by platform:

```text
home-manager/
├── nixos/                 # NixOS-specific modules
│   ├── frank.nix          # Main config (imports shared + NixOS modules)
│   ├── niri/              # Window manager binds, layout, rules, startup
│   ├── noctalia/          # Native Noctalia V5 shell + theme bridge
│   ├── stylix.nix         # Theming with dark/light specialisations
│   ├── nushell.nix        # Shell integration
│   └── */                 # Other NixOS-specific modules
├── darwin/                # Darwin-specific modules
│   ├── frank.nix          # Main config (imports shared + Darwin modules)
│   ├── ghostty.nix        # Terminal (Homebrew package)
│   ├── nushell.nix        # Shell (Nix PATH setup)
│   ├── packages.nix       # CLI packages
│   ├── zed.nix            # Zed editor
│   ├── zellij.nix         # Terminal multiplexer
│   └── zen-browser.nix    # Browser with extension policies
├── shared/                # Cross-platform modules
│   ├── default.nix        # Shared import entry point
│   ├── nushell.nix        # Shell (shared config, keybindings, carapace)
│   ├── atuin.nix          # Shell history
│   ├── git.nix            # Version control
│   ├── gh.nix             # GitHub CLI + gh-dash
│   ├── starship.nix       # Prompt
│   ├── ssh.nix            # SSH config
│   ├── claude-code/       # Claude Code configuration
│   ├── navi/              # Cheatsheet tool
│   └── */                 # Other shared configs
└── mcp/                   # MCP server configurations
    └── anytype.nix        # Anytype MCP server
```

## Overlays and Packages

Local packages live in `pkgs/`; `overlays/` wires them into `pkgs` and applies
small upstream fixes. `lib/overlays.nix` composes the shared, NixOS-only and
Darwin-only lists.

```text
overlays/
├── niri.nix                 # Niri package (flake version)
├── claude-code.nix          # Claude Code customizations
├── profile-sync-daemon.nix  # PSD with Zen Browser support
├── openchamber.nix          # OpenChamber desktop/web build
├── gh-enhance.nix           # GitHub enhance extension
└── */                       # Other overlays

pkgs/
├── openchamber/             # Desktop release packaging (Darwin/x86_64-linux)
├── cliamp/                  # CLI music player
├── pi-coding-agent/         # Pi coding agent
├── worktrunk/               # Git worktree CLI
└── */                       # Other local packages
```

## Shared Resources

```text
shared/
├── caches.nix         # Single source of truth for binary caches (mirrored in flake.nix)
└── themes.nix         # Central base16 theme definitions (Catppuccin Mocha/Latte)
```

## Scripts Directory

```text
scripts/
├── update-*.sh                # Package update scripts used by `flake-update`
├── show-changelogs.*          # Show changelogs after a switch
├── take-readme-screenshots.*  # Screenshot automation (Noctalia IPC)
├── smoke-test-pi-package.sh   # Pi package smoke test
└── test-pi-extensions.sh      # Pi extension test runner
```

## Flake Outputs and Checks

- `nixosConfigurations.framework` and `nixosConfigurations.hermi`
- `darwinConfigurations.macbook`
- `checks.<system>.*` for cache policy, kernel-provider compatibility, Noctalia
  theme/lock invariants, Umbriel, Pi packaging and host-specific runtime tests

The checks are currently defined directly in `flake.nix`; `nix flake check`
evaluates them, while CI builds the cheap subset explicitly.

## Configuration Flow

1. `lib/host-inventory.nix` declares the available NixOS and Darwin hosts.
2. `flake.nix` maps that inventory through `lib/hosts.nix` / `lib/darwin.nix`.
3. `hosts/<host>/default.nix` imports hardware, `modules/` and profiles.
4. `hosts/<host>/home.nix` wires Home Manager, shared modules and host args.
5. `home-manager/<platform>/frank.nix` imports shared + platform modules.

`hermi` is built through `nixos-raspberrypi.lib.nixosSystem` because its module
and package set must stay on the Raspberry Pi pin; it does not import the shared
desktop profiles.

## Channel Strategy

This configuration uses `nixpkgs-unstable` as the main channel for all packages,
providing access to the latest versions while accepting slightly less stability.
`hermi` tracks the `nixos-raspberrypi` pin, and `chaotic` supplies the CachyOS
kernel from its own nixpkgs pin (kept deliberately un-followed for cache hits).

## Key Concepts

- **System modules** (`modules/`) configure system-wide settings (NixOS only)
- **Home Manager modules** (`home-manager/`) configure user-specific settings
- **Shared modules** (`home-manager/shared/`) work on both NixOS and Darwin
- **Overlays** modify or replace packages from nixpkgs
- **Specialisations** (via Stylix) enable dark/light theme switching without rebuilds
- **Noctalia V5** owns the shell, notifications, wallpaper and runtime palette;
  Stylix supplies fonts, cursor, icons and the remaining declarative consumers
