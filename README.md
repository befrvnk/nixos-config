# NixOS Configuration

Personal NixOS configuration for a Framework 13 laptop with the Niri window manager.

## Quick Start

```bash
# Rebuild system configuration
sudo nixos-rebuild switch --flake .#framework

# Update all flake inputs
nix flake update

# Format Nix files
nix develop -c nixfmt **/*.nix flake.nix
```

## Desktop Environment

This configuration uses a minimal, keyboard-driven Wayland desktop:

### Niri (Window Manager)

[Niri](https://github.com/YaLTeR/niri) is a scrollable-tiling Wayland compositor. Windows are arranged in columns that scroll horizontally, similar to PaperWM.

Key features in this setup:
- Workspaces numbered 1-9, accessible via `Mod+1` through `Mod+9`
- Transparent workspace backgrounds (wallpaper shows through)
- 12px gaps between windows
- Rounded corners (12px radius)
- Variable refresh rate on external monitors
- Overview mode (`Mod+O`) shows all windows

### Vicinae (Application Launcher)

[Vicinae](https://github.com/coco/vicinae) is the application launcher. Press `Mod+Space` to open it and start typing to search for applications.

### Ironbar (Status Bar)

[Ironbar](https://github.com/JakeStanger/ironbar) displays system information at the top of the screen:

- **Workspaces** - Click to switch workspaces
- **Clock** - Current time
- **System stats** - CPU %, Memory %, Temperature
- **WiFi status** - Connection indicator
- **Notifications** - Unread count with popup history
- **Bluetooth** - Connection status
- **Volume** - Current level (click to adjust)
- **Battery** - Percentage and charging state

## Keyboard Shortcuts

### Essential

| Shortcut | Action |
|----------|--------|
| `Mod+Space` | Open application launcher (Vicinae) |
| `Mod+G` | Open terminal (Ghostty) |
| `Mod+Q` | Close focused window |
| `Mod+O` | Toggle overview mode |
| `Mod+Shift+E` | Exit Niri |
| `Mod+Shift+S` | Suspend system |

### Window Navigation

| Shortcut | Action |
|----------|--------|
| `Mod+H/J/K/L` or `Mod+Arrows` | Focus column/window in direction |
| `Mod+Ctrl+H/J/K/L` | Move window in direction |
| `Mod+Home/End` | Focus first/last column |

### Window Layout

| Shortcut | Action |
|----------|--------|
| `Mod+F` | Maximize column |
| `Mod+Shift+F` | Toggle fullscreen |
| `Mod+V` | Toggle floating mode |
| `Mod+W` | Toggle tabbed column display |
| `Mod+C` | Center column |
| `Mod+R` | Switch preset column widths (75%/50%/25%) |
| `Mod+Minus/Equal` | Decrease/increase column width |

### Workspaces

| Shortcut | Action |
|----------|--------|
| `Mod+1-9` | Switch to workspace 1-9 |
| `Mod+Ctrl+1-9` | Move window to workspace 1-9 |
| `Mod+Tab` | Previous workspace |
| `Mod+U/I` or `Mod+PageUp/Down` | Previous/next workspace |

### Multi-Monitor

| Shortcut | Action |
|----------|--------|
| `Mod+Shift+H/L` or `Mod+Shift+Left/Right` | Focus monitor |
| `Mod+Shift+Ctrl+H/L` | Move window to monitor |

### Media & Hardware

| Shortcut | Action |
|----------|--------|
| `XF86AudioRaiseVolume/LowerVolume` | Adjust volume |
| `XF86AudioMute` | Toggle mute |
| `XF86MonBrightnessUp/Down` | Adjust brightness |
| `XF86AudioPlay/Prev/Next` | Media controls |

### Screenshots

| Shortcut | Action |
|----------|--------|
| `Print` | Screenshot area to clipboard |
| `Ctrl+Print` | Screenshot screen to clipboard |
| `Alt+Print` | Screenshot window to clipboard |

## Network Management

WiFi and Bluetooth connections are managed via terminal commands:

### WiFi (NetworkManager)

```bash
# List available networks
nmcli device wifi list

# Connect to a network
nmcli device wifi connect "SSID" password "password"

# Show saved connections
nmcli connection show

# Connect to a saved network
nmcli connection up "connection-name"

# Disconnect
nmcli device disconnect wlan0
```

### Bluetooth (bluetoothctl)

```bash
# Open bluetooth control
bluetoothctl

# Inside bluetoothctl:
power on           # Enable bluetooth
scan on            # Start scanning
devices            # List discovered devices
pair XX:XX:XX:XX   # Pair with device
connect XX:XX:XX:XX # Connect to device
disconnect         # Disconnect current device
```

## Installed Software

### System Packages

Core utilities installed at the system level in `modules/system/packages.nix`:

- **Shell:** zsh
- **Editor:** vim
- **Version Control:** git
- **Networking:** wget, networkmanager
- **Security:** tpm2-tss, sbctl (secure boot)

### User Applications

Installed via home-manager in `home-manager/packages.nix`:

#### Productivity
- **anytype** - Note-taking and knowledge management
- **ticktick** - Task management
- **signal-desktop** - Encrypted messaging
- **zapzap** - WhatsApp client
- **slack** - Team communication
- **discord** - Voice and text chat
- **spotify** - Music streaming

#### Web Browsers
- **zen-browser** - Privacy-focused Firefox fork
- **chromium** - For compatibility testing

#### Development
- **zed-editor** - Modern code editor
- **helix** - Modal terminal editor
- **jetbrains.idea-community-bin** - Android development
- **gh** - GitHub CLI
- **nil**, **nixd** - Nix language servers

#### AI Tools
- **claude-code** - Anthropic's AI coding assistant
- **gemini-cli** - Google's Gemini AI

#### Terminal & CLI
- **ghostty** - GPU-accelerated terminal
- **bat** - Syntax-highlighted cat
- **eza** - Modern ls replacement
- **fd** - Fast find alternative
- **fzf** - Fuzzy finder
- **htop** - Process viewer
- **tree** - Directory tree viewer
- **yazi** - Terminal file manager
- **superfile** - Terminal file manager with preview
- **lf** - Terminal file manager
- **navi** - Interactive cheatsheet
- **neofetch** - System info display
- **starship** - Cross-shell prompt

#### File Management
- **nautilus** - GNOME file manager
- **sushi** - Quick file previewer

#### Media
- **playerctl** - Media player control
- **pavucontrol** - PulseAudio volume control
- **upscayl** - AI image upscaler
- **imagemagick** - Image manipulation

#### Desktop Environment
- **niri** - Scrollable-tiling Wayland compositor
- **ironbar** - Customizable status bar
- **vicinae** - Application launcher
- **dunst** - Notification daemon
- **swaylock** - Screen locker
- **swaybg** - Wallpaper manager
- **brightnessctl** - Brightness control

#### Theming
- **papirus-icon-theme** - Icon theme
- **stylix** - Automatic application theming

#### Security
- **1password** - Password manager (GUI and CLI)
- **gnome-keyring** - Secure credential storage

### Android Development

Optional Android development environment (`home-manager/android.nix`):
- Android Studio Canary
- Android SDK (build-tools, platform-tools, emulator)
- Platform SDK for Android 34

## Configuration Structure

### Overview

```
nixos-config/
├── flake.nix              # Entry point - defines inputs and outputs
├── hosts/                 # Machine-specific configurations
│   └── framework/         # Framework laptop config
├── modules/               # System-level NixOS modules
│   ├── desktop/           # Display manager, compositor
│   ├── hardware/          # Hardware-specific configs
│   ├── services/          # System services
│   ├── system/            # Core system settings
│   └── theming/           # System-wide theming
├── home-manager/          # User-level configurations
│   ├── frank.nix          # Main user config
│   ├── packages.nix       # User packages
│   ├── niri/              # Window manager config
│   ├── ironbar/           # Status bar config
│   └── ...                # Application configs
├── overlays/              # Package modifications
└── docs/                  # Detailed documentation
```

### System vs Home-Manager

This configuration separates concerns between system-level and user-level settings:

**System Level** (`modules/`):
- Boot configuration and kernel parameters
- Hardware drivers and firmware
- System services (greetd, darkman, pipewire, bluetooth)
- Network management
- Power management (TLP)
- Security (PAM, polkit, TPM)
- System users and groups

**Home-Manager Level** (`home-manager/`):
- User applications and packages
- Shell configuration (zsh, starship)
- Application settings (git, ssh, editors)
- Window manager keybindings and rules
- Desktop environment (ironbar, vicinae, dunst)
- User services (swayidle, battery notifications)
- Theming specializations (dark/light modes)

## Features

### Theming

- **Stylix** automatically themes all applications
- **Catppuccin** color scheme (Mocha dark, Latte light)
- **Darkman** switches themes based on time of day
- Light/dark mode without rebuild using specializations
- Fonts: JetBrainsMono Nerd Font, Noto Sans/Serif

### Security

- **Secure Boot** with Lanzaboote
- **TPM2 auto-unlock** for LUKS encrypted disk
- **Fingerprint authentication** for sudo, login, and screen lock
- **1Password** integration with polkit

### Power Management

- TLP for automatic power optimization
- Performance mode on AC, powersave on battery
- CPU boost disabled on battery
- Smart screen lock (won't lock during media playback)
- Auto-suspend after 5 minutes idle

### Notifications

- **Dunst** for desktop notifications
- Battery warnings at 5%, 20%, and 100%
- Notification history accessible from status bar

## Hardware

- **Laptop:** Framework 13, Ryzen AI 9 HX 370
- **RAM:** 2x32GB DDR5-5600
- **Storage:** 1TB WD_BLACK SN850X NVMe
- **Keyboard:** Nuphy Air75 V3 (configured via [nuphy.io](https://nuphy.io))
- **Mouse:** Logitech G403
- **Monitor:** Dough Spectrum 4K 144Hz 27"

### Custom Keyboard Layout

US layout with German umlauts via Right Alt:
- `Alt+A` = ä
- `Alt+O` = ö
- `Alt+U` = ü
- `Alt+S` = ß
- `Alt+E` = €

## Documentation

Detailed guides for specific topics:

- [Repository Structure](./docs/structure.md) - Detailed configuration organization
- [Adding Packages](./docs/adding-packages.md) - How to add system and user packages
- [Adding a New Host](./docs/new-host.md) - Configure additional machines
- [Secure Boot with TPM](./docs/secure-boot.md) - Secure boot setup
- [Fingerprint Setup](./docs/fingerprint-setup.md) - Fingerprint authentication
- [Stylix & Darkman](./docs/stylix-darkman-setup.md) - Theme switching
- [Development Environment](./docs/development-environment.md) - Dev shell and formatting
- [Screen Lock & Suspend](./docs/screen-lock-and-suspend.md) - Lock screen behavior
- [External Monitor Brightness](./docs/external-monitor-brightness.md) - DDC/CI control

## Getting Started with Nix

New to Nix? Here are the key concepts:

### Flakes

This configuration uses Nix flakes for reproducible builds. The `flake.nix` file defines:
- **inputs** - External dependencies (nixpkgs, home-manager, etc.)
- **outputs** - What this flake produces (NixOS configurations)

### Declarative Configuration

Everything is defined in `.nix` files. To change your system:
1. Edit the relevant `.nix` file
2. Run `sudo nixos-rebuild switch --flake .#framework`
3. Changes take effect immediately (some require logout/reboot)

### Common Tasks

```bash
# Rebuild after editing configuration
sudo nixos-rebuild switch --flake .#framework

# Test configuration without making it default
sudo nixos-rebuild test --flake .#framework

# Update all packages
nix flake update
sudo nixos-rebuild switch --flake .#framework

# Roll back to previous generation
sudo nixos-rebuild switch --rollback

# List generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Garbage collect old generations
sudo nix-collect-garbage -d
```

### Where to Add Things

- **System package:** `modules/system/packages.nix`
- **User package:** `home-manager/packages.nix`
- **New application config:** Create `home-manager/appname.nix` and import in `frank.nix`
- **System service:** Create in `modules/services/`
- **Hardware config:** Create in `modules/hardware/`

See [Adding Packages](./docs/adding-packages.md) for detailed instructions.
