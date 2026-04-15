# Ironbar Configuration

Customizable Wayland bar for Niri compositor with custom toggle behavior and workarounds for known bugs.

## Overview

This ironbar setup includes:
- **Overview-only mode**: Bar only visible when Niri's overview (workspace expose) is active
- **Custom volume module**: Workaround for PulseAudio crash bug in built-in volume module
- **Stylix integration**: Automatic color theming from system theme
- **Custom modules**: WiFi, battery, notifications, and volume status

## Files

- `default.nix` - Home Manager module configuration
- `config.json` - Ironbar module and layout configuration
- `style.css` - Bar styling (auto-merged with Stylix colors)
- `toggle-ironbar.py` - Python script for Niri overview integration
- `modules/*/` - Custom module scripts
- `CONFIG.md` - Detailed config.json documentation
- `modules/volume/README.md` - Volume module workaround documentation

## Key Features

### 1. Niri Overview Integration

**Behavior:** Ironbar is hidden by default and only appears when you open Niri's overview mode (workspace expose).

**Implementation:**
- `toggle-ironbar.py` listens to Niri's event stream
- Detects `OverviewOpenedOrClosed` events
- Sends IPC commands to ironbar to show/hide the bar
- Runs as a systemd user service

**Service:** `systemd.user.services.ironbar`

### 2. Event-Driven Volume Display

**Problem:** Ironbar's built-in volume module has a critical crash bug.
**Issue:** https://github.com/JakeStanger/ironbar/issues/875 (Open, Critical)

**Solution:** Keep the volume display separate from volume control:
1. `volume-ctl` (from the Niri config) changes volume and updates `~/.cache/volume-status`
2. Niri runs `volume-ctl init` at session startup to seed the cache
3. Ironbar polls a tiny reader script every second
4. The reader script only returns the cached label, so the bar never talks to PipeWire directly

**Details:** See `modules/volume/README.md`

### 3. Stylix Color Integration

Ironbar's CSS automatically includes Stylix color variables:
```css
@define-color base00 #...;  /* Background */
@define-color base05 #...;  /* Foreground */
/* etc. */
```

These are prepended to `style.css` at build time, allowing the bar to match your system theme.

## Custom Modules

All custom modules use shell scripts that output formatted text with Nerd Font icons:

| Module | Script | Update Interval | Description |
|--------|--------|-----------------|-------------|
| WiFi | `modules/wifi/wifi-status.sh` | 5s | Shows SSID and signal strength |
| Battery | `modules/battery/battery-status.sh` | 5s | Shows battery level and charging status |
| Notifications | `modules/notifications/*.sh` | 2s | Shows unread count, history popup |
| **Volume** | `modules/volume/volume-status.sh` | **1s (cache read)** | **Reads `~/.cache/volume-status` written by `volume-ctl`** |

## Building

This configuration is managed by Home Manager:

```bash
home-manager switch
```

After rebuild, ironbar will restart automatically via systemd.

## Debugging

### Check if ironbar is running
```bash
systemctl --user status ironbar
```

### View logs
```bash
journalctl --user -u ironbar -f
```

### Test volume script manually
```bash
bash ~/.config/ironbar/modules/volume/volume-status.sh
```

### Check IPC connection
```bash
ls -la /run/user/$(id -u)/ironbar-ipc.sock
```

## Known Issues

### Volume Module Crash (WORKAROUND APPLIED)

**Status:** Event-driven cache reader implemented to avoid the crash path entirely.

**Tracking:** https://github.com/JakeStanger/ironbar/issues/875

**Architecture:**
- Keybindings call `volume-ctl` instead of invoking ironbar's built-in module
- `volume-ctl` drives SwayOSD and updates `~/.cache/volume-status`
- Ironbar reads the cache file once per second
- The bar never calls `wpctl` or PipeWire directly

**When fixed:** Can switch back to the built-in module if desired, but the cache-based design is simple and reliable.

## Performance

- **Toggle script:** Minimal overhead, event-driven (not polling)
- **Volume module:** Near-zero overhead (reads a cache file)
- **Total bar CPU:** <1% CPU when visible
- **Memory:** ~30-40MB resident
- **DBus impact:** No bar-side PipeWire polling for volume updates

## Dependencies

- `pkgs.ironbar` - The bar itself
- `pkgs.jq` - JSON parsing for notifications
- `pkgs.wireplumber` - wpctl command used by Niri helpers and display scripts
- `pkgs.python3` - For toggle script
- Nerd Font - For icons in custom modules
