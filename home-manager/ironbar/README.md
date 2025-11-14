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

### 2. Volume Module Workaround

**Problem:** Ironbar's built-in volume module has a critical crash bug.

**Error:**
```
Assertion 'e->mainloop->n_enabled_defer_events > 0' failed at mainloop.c:261
```

**Issue:** https://github.com/JakeStanger/ironbar/issues/875 (Open, Critical)

**Solution:** Custom script using `wpctl` instead of PulseAudio bindings.

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
| **Volume** | `modules/volume/volume-status.sh` | **200ms** | **Shows volume level and mute state** |

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

**Status:** Custom module implemented to avoid the crash.

**Tracking:** https://github.com/JakeStanger/ironbar/issues/875

**When fixed:** Switch back to built-in module:
1. Replace custom volume module in `config.json` with:
   ```json
   {"type": "volume", "max_volume": 100}
   ```
2. Remove `pkgs.wireplumber` from `default.nix`
3. Remove volume script configuration from `default.nix`

## Performance

- **Toggle script:** Minimal overhead, event-driven (not polling)
- **Volume module:** ~0.1% CPU at 200ms polling interval
- **Total bar CPU:** <1% CPU when visible
- **Memory:** ~30-40MB resident

## Dependencies

- `pkgs.ironbar` - The bar itself
- `pkgs.jq` - JSON parsing for notifications
- `pkgs.wireplumber` - wpctl command for volume module
- `pkgs.python3` - For toggle script
- Nerd Font - For icons in custom modules
