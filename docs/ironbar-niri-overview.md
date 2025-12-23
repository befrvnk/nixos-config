# Ironbar with Niri Overview Mode Integration

This document explains our ironbar configuration that only appears during Niri's overview (workspace switcher) mode.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Configuration Details](#configuration-details)
- [How It Works](#how-it-works)
- [Making Changes](#making-changes)
- [Troubleshooting](#troubleshooting)
- [Custom Modules Reference](#custom-modules-reference)
- [Overview Mode Watcher Service](#overview-mode-watcher-service)
- [Comparison with Waybar](#comparison-with-waybar)

## Overview

### What is Ironbar?

Ironbar is a customizable GTK4-based status bar for Wayland compositors, written in Rust. It provides:
- Workspace indicators (with Niri support)
- Window information
- System monitoring (CPU, memory, battery, etc.)
- Network and Bluetooth status
- Volume control
- System tray
- Custom modules via scripts

### Our Setup

We've configured ironbar to:
1. **Only appear during Niri overview mode** (hidden during normal desktop use)
2. **Display on the top** with transparency and custom styling
3. **Use Ironbar's native IPC** for show/hide control
4. **Integrate with system services** (UPower for battery, bluez for Bluetooth)

This creates a clean desktop experience where the bar only appears when switching workspaces, **without the black bar artifacts** that waybar had on empty workspaces.

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Niri Compositor                      │
│  - Monitors overview mode state                         │
│  - Emits OverviewOpenedOrClosed events                  │
└──────────────────┬──────────────────────────────────────┘
                   │ IPC via NIRI_SOCKET
                   │
┌──────────────────▼──────────────────────────────────────┐
│            toggle-ironbar.py script                     │
│  - Subscribes to Niri event stream                      │
│  - Starts ironbar process                               │
│  - Dynamically detects bar name via IPC                 │
│  - Sends show/hide commands on overview state change    │
└──────────────────┬──────────────────────────────────────┘
                   │ IPC via /run/user/UID/ironbar-ipc.sock
                   │
┌──────────────────▼──────────────────────────────────────┐
│                    Ironbar                              │
│  - Listens on IPC socket for commands                   │
│  - Responds to show/hide commands                       │
│  - Displays modules: workspaces, cpu, battery, etc.     │
└─────────────────────────────────────────────────────────┘
```

### File Structure

```
home-manager/
├── ironbar/
│   ├── default.nix           # Nix module with systemd service
│   ├── config.json           # Ironbar configuration
│   ├── style.css             # Custom CSS styling
│   └── toggle-ironbar.py     # Python script for overview-mode toggle
└── frank.nix                 # Imports ironbar module

modules/
└── services/
    └── bluetooth.nix         # Enables bluez and upower services
```

## Configuration Details

### Ironbar Configuration (`home-manager/ironbar/config.json`)

```json
{
  "position": "top",
  "height": 40,
  "icon_theme": "Papirus-Dark",
  "start": [
    { "type": "workspaces" },
    { "type": "focused" }
  ],
  "center": [
    { "type": "clock", "format": "%H:%M" }
  ],
  "end": [
    { "type": "sys_info" },
    { "type": "network_manager" },
    { "type": "bluetooth" },
    { "type": "volume" },
    { "type": "battery" },
    { "type": "tray" }
  ]
}
```

### Custom Styling (`home-manager/ironbar/style.css`)

The CSS uses Catppuccin Mocha colors with transparency:
- Main bar: `rgba(30, 30, 46, 0.85)` background with blue accent border
- Modules: Transparent backgrounds with rounded corners
- Different colors for each module type (CPU=green, Network=cyan, Battery=green/blue, etc.)
- No hover effects on clickable items

**Important:** GTK CSS doesn't support `@keyframes` animations. Use static styles only.

### Toggle Script (`home-manager/ironbar/toggle-ironbar.py`)

The script:
1. Connects to Niri's IPC socket
2. Requests the event stream
3. Starts ironbar process
4. Queries ironbar IPC to get the current bar name (e.g., `bar-20`)
5. Hides the bar initially
6. Listens for `OverviewOpenedOrClosed` events
7. Sends IPC commands to show/hide the bar

#### IPC Commands

The script uses Ironbar's native IPC protocol:

**Show bar:**
```json
{"command": "bar", "subcommand": "show", "name": "bar-20"}
```

**Hide bar:**
```json
{"command": "bar", "subcommand": "hide", "name": "bar-20"}
```

**List bars (to get name):**
```json
{"command": "list"}
```

### Systemd Service

```nix
systemd.user.services.ironbar = {
  Unit = {
    Description = "Ironbar with niri overview-only mode";
    PartOf = [ "graphical-session.target" ];
    After = [ "graphical-session.target" ];
    ConditionEnvironment = "WAYLAND_DISPLAY";
  };

  Service = {
    Type = "simple";
    ExecStart = "${toggleScript}";
    Restart = "on-failure";
    RestartSec = "5s";
  };

  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};
```

The service starts the toggle script (not ironbar directly), which then manages ironbar's lifecycle.

## How It Works

### Step-by-Step Flow

1. **System Startup**
   - Systemd starts the `ironbar.service`
   - The service executes `toggle-ironbar.py`

2. **Script Initialization**
   - Script connects to `$NIRI_SOCKET`
   - Subscribes to event stream with `"EventStream"` message
   - Starts ironbar process
   - Queries ironbar IPC to get bar name (dynamically determined)
   - Sends initial `hide` command to ironbar

3. **User Opens Overview (Super+Tab)**
   - Niri emits `{"OverviewOpenedOrClosed": {"is_open": true}}`
   - Script receives event and sends show command via IPC
   - Ironbar becomes visible

4. **User Closes Overview**
   - Niri emits `{"OverviewOpenedOrClosed": {"is_open": false}}`
   - Script receives event and sends hide command via IPC
   - Ironbar becomes hidden

### Why Ironbar IPC Instead of Signals?

Unlike waybar (which uses SIGUSR1/SIGUSR2), ironbar has native IPC commands for show/hide. This provides:
- **Cleaner implementation**: Direct API instead of signal workaround
- **Better state control**: Explicit show/hide commands
- **No visual artifacts**: Ironbar properly removes its surface when hidden
- **Dynamic bar name detection**: Script queries IPC to get current bar name

## Making Changes

### Updating Configuration or Styles

**IMPORTANT:** Do NOT use `ironbar reload` when the bar is controlled by the toggle script. It will create a new bar instance that won't be controlled by the toggle script.

#### Correct Workflow:

1. **Edit configuration files**:
   ```bash
   vim ~/nixos-config/home-manager/ironbar/config.json
   vim ~/nixos-config/home-manager/ironbar/style.css
   ```

2. **Rebuild to update symlinks**:
   ```bash
   sudo nixos-rebuild switch --flake .#
   # OR for just home-manager:
   home-manager switch --flake .#frank
   ```

3. **Restart the service** (required!):
   ```bash
   systemctl --user restart ironbar
   ```

#### Why Restart Instead of Reload?

- `ironbar reload` creates a new bar instance with a new ID (e.g., `bar-20` → `bar-21`)
- The toggle script is still running and controlling the old bar ID
- The new bar won't be hidden or controlled by the toggle script
- **Solution:** Restart the systemd service, which restarts both the toggle script and ironbar

### Adding New Modules

Edit `config.json` and add modules to `start`, `center`, or `end` arrays. See [Ironbar documentation](https://github.com/JakeStanger/ironbar/wiki) for available modules.

After editing, rebuild and restart:
```bash
sudo nixos-rebuild switch --flake .#
systemctl --user restart ironbar
```

### Changing Styling

Edit `style.css` with any GTK CSS properties. Remember:
- Use `rgba()` for transparency
- No `@keyframes` animations (not supported in GTK CSS)
- Module classes: `.module-{type}` (e.g., `.module-clock`, `.module-battery`)
- State classes: `.disconnected`, `.charging`, `.muted`, `.critical`, etc.

After editing, rebuild and restart:
```bash
sudo nixos-rebuild switch --flake .#
systemctl --user restart ironbar
```

## Troubleshooting

### Ironbar Not Appearing in Overview

**Check 1**: Verify the service is running
```bash
systemctl --user status ironbar
```

**Check 2**: Check toggle script logs
```bash
journalctl --user -u ironbar -f
```

You should see messages like:
```
Starting ironbar toggle script...
Connected to niri socket
Starting ironbar...
Detected bar name: bar-20
Hiding ironbar initially...
Listening for niri overview events...
```

**Check 3**: Test IPC manually
```bash
# Get bar name
echo '{"command":"list"}' | nc -U /run/user/1000/ironbar-ipc.sock

# Show bar manually
echo '{"command":"bar","subcommand":"show","name":"bar-20"}' | nc -U /run/user/1000/ironbar-ipc.sock
```

### Ironbar Stuck Visible

This usually happens after using `ironbar reload`. The toggle script is controlling the old bar instance.

**Solution:**
```bash
systemctl --user restart ironbar
```

### Bar Name Changed

The toggle script dynamically detects the bar name on startup. If you see errors about bar names in logs, restart the service:
```bash
systemctl --user restart ironbar
```

### CSS Not Loading

Check logs for CSS errors:
```bash
journalctl --user -u ironbar | grep -i "css\|style"
```

Common issues:
- `@keyframes` animations (not supported - remove them)
- Invalid GTK CSS properties
- Syntax errors in CSS

### Module Not Working

**Missing service errors:**
- Bluetooth: Ensure `bluez` is enabled (`services.bluetooth.enable = true`)
- Battery: Ensure `upower` is enabled (`services.upower.enable = true`)
- Notifications: Ironbar's notifications module requires `swaync` (we use dunst instead, so this module is disabled)

Check which services are enabled:
```bash
systemctl --user list-units | grep -E "bluez|upower"
```

### Icons Not Showing

Ensure Papirus icon theme is installed:
```bash
ls ~/.nix-profile/share/icons/Papirus*
```

If missing, rebuild:
```bash
sudo nixos-rebuild switch --flake .#
```

## Custom Modules Reference

This configuration uses several custom modules instead of Ironbar's built-in alternatives. Here's a reference for each.

### Volume Module

**Location:** `home-manager/ironbar/modules/volume/`

**Why custom?** The built-in volume module has issues with PulseAudio/PipeWire compatibility and can crash.

**Implementation:**
- Uses `wpctl` (WirePlumber) for reliable audio control
- Script outputs JSON: `{"icon": "󰕾", "volume": 75, "muted": false}`
- Updates on volume key presses via custom script integration

**Files:**
- `default.nix` - Module configuration
- Volume control integrated with `volume-ctl` script in niri keybindings

**Key code pattern:**
```bash
# Get volume level
wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{print int($2 * 100)}'

# Check if muted
wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED
```

### Storage Module

**Location:** `home-manager/ironbar/modules/storage/`

**Purpose:** Shows mounted removable devices (USB drives, SD cards) in the status bar.

**Implementation:**
- Uses `lsblk -J` for JSON output of block devices
- Filters for removable devices (`rm == true`)
- Shows mount point and size
- Integrates with udiskie for unmount actions

**Files:**
- `default.nix` - Module configuration with script embedding
- Uses `jq` for JSON parsing

**Key code pattern:**
```bash
# Get mounted removable devices
lsblk -J -o NAME,MOUNTPOINT,SIZE,RM,TYPE | \
  jq -r '.blockdevices[] |
    select(.rm == true) |
    .children[]? |
    select(.mountpoint != null)'
```

### Battery Module with Platform Profiles

**Location:** `home-manager/ironbar/modules/battery/`

**Features:**
- Uses Ironbar's built-in `upower` module for battery status
- Custom popup with platform profile switching
- Scripts for reading/setting ACPI platform profiles

**Files:**
- `default.nix` - Module configuration
- `get-profile.sh` - Reads current profile from `/sys/firmware/acpi/platform_profile`
- `set-profile.sh` - Sets profile via `pkexec` for authorization

**Platform Profile Switching:**
```bash
# Available profiles: power-saver, balanced, performance

# Read current
cat /sys/firmware/acpi/platform_profile

# Set (requires polkit auth)
pkexec bash -c "echo 'balanced' > /sys/firmware/acpi/platform_profile"
```

See [AMD P-State & Power](./amd-pstate-configuration.md#platform-profile-switching) for more details.

### Notifications Module

**Purpose:** Shows unread notification count from dunst.

**Implementation:**
- Queries dunst history via `dunstctl history`
- Displays count badge on notification icon
- Click opens notification history popup

## Overview Mode Watcher Service

In addition to the toggle script, a separate service monitors niri's overview mode to manage popup behavior.

### Purpose

When exiting Niri's overview mode, any open Ironbar popups (volume slider, battery popup, etc.) should close to prevent visual clutter.

### Architecture

```
┌───────────────────────────────────────────────────────────────┐
│              Niri Overview Watcher                             │
├───────────────────────────────────────────────────────────────┤
│                                                                │
│  ┌──────────────┐    ┌───────────────┐    ┌────────────────┐ │
│  │    Niri      │───>│ niri-overview │───>│    Ironbar     │ │
│  │ event-stream │    │ watcher.sh    │    │  close popups  │ │
│  └──────────────┘    └───────────────┘    └────────────────┘ │
│         │                    │                                 │
│  OverviewChanged         Parse JSON                           │
│  {is_open: false}        with jq                              │
│                                                                │
└───────────────────────────────────────────────────────────────┘
```

### Service Configuration

**Location:** `home-manager/ironbar/modules/niri-overview-watcher/default.nix`

```nix
systemd.user.services.niri-overview-watcher = {
  Unit = {
    Description = "Niri overview watcher - closes Ironbar popups on overview exit";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${overviewWatcherScript}";
    Restart = "on-failure";
    RestartSec = "5";
  };
  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};
```

### Script Logic

```bash
# Wait for niri to be ready
sleep 2

# Monitor niri events
niri msg --json event-stream | while read -r event; do
  # Check if overview was closed
  if echo "$event" | jq -e '.OverviewChanged.is_open == false' >/dev/null; then
    # Close any open popups
    ironbar set-visible popup false
  fi
done
```

### Why This Is Needed

Without this service:
- Opening a popup (e.g., battery details) then entering overview leaves popup visible
- Exiting overview with popup still open creates visual clutter
- User has to manually close popups

With this service:
- Popups automatically close when exiting overview
- Clean transition back to normal desktop
- Better user experience

### Verification

```bash
# Check service status
systemctl --user status niri-overview-watcher

# Watch logs
journalctl --user -u niri-overview-watcher -f

# Test: Open a popup in Ironbar, enter overview mode, exit
# Popup should close automatically
```

### Related Keybinding

The `Mod+Tab` keybinding in `home-manager/niri/binds.nix` also explicitly closes popups:

```nix
"Mod+Tab".action = spawn [
  "${pkgs.bash}/bin/bash"
  "-c"
  "${closePopupsScript}; ${lib.getExe pkgs.niri} msg action toggle-overview"
];
```

This provides immediate popup closing when entering overview, while the watcher service handles closing popups when exiting.

## Comparison with Waybar

### Advantages of Ironbar

- ✅ **No black bar artifacts** on empty workspaces
- ✅ **Native IPC API** for show/hide (cleaner than SIGUSR signals)
- ✅ **Dynamic bar name detection** (no hardcoded IDs)
- ✅ **GTK4** (modern toolkit)
- ✅ **Active Niri support** (workspace module works)

### Differences

- ⚠️ **Different configuration format** (JSON instead of Nix attributes)
- ⚠️ **Different CSS structure** (GTK4 instead of GTK3)
- ⚠️ **No signal-based control** (uses IPC instead)
- ⚠️ **Requires service restart** for config changes (can't use `ironbar reload`)

## Related Configuration Files

- `home-manager/ironbar/default.nix` - Main Ironbar module
- `home-manager/ironbar/toggle-ironbar.py` - Overview mode toggle script
- `home-manager/ironbar/modules/volume/` - Custom volume module
- `home-manager/ironbar/modules/storage/` - Storage/removable media module
- `home-manager/ironbar/modules/battery/` - Battery with platform profiles
- `home-manager/ironbar/modules/niri-overview-watcher/` - Popup close watcher
- `home-manager/niri/binds.nix` - Keybindings including overview toggle

## Related Documentation

- [Ironbar Wiki](https://github.com/JakeStanger/ironbar/wiki)
- [Ironbar IPC Commands](https://github.com/JakeStanger/ironbar/wiki/controlling-ironbar)
- [Niri IPC Documentation](https://github.com/YaLTeR/niri/wiki/IPC)
- [AMD P-State & Platform Profiles](./amd-pstate-configuration.md) - Power profile switching details
- [Stylix & Darkman](./stylix-darkman-setup.md) - Theme integration with Ironbar
