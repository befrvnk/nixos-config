# Ghostty Startup Delay Issue

## Summary

Ghostty experiences a 5-second startup delay due to `xdg-desktop-portal-gtk` service failing at boot and requiring D-Bus activation timeout.

**Status:** Known issue, planned to be resolved when switching from DMS to ironbar.

## The Problem

When launching Ghostty, there is a noticeable delay of approximately 5 seconds before the window appears. This delay occurs consistently on every launch.

### Observed Behavior

```bash
# Ghostty binary itself is fast:
$ time ghostty --help > /dev/null 2>&1
0.02s user 0.02s system 94% cpu 0.038 total

# But actual window launch takes ~5 seconds
$ ghostty  # Takes ~5 seconds to appear
```

## Root Cause

The delay is caused by the interaction between three components:

1. **Ghostty's theme configuration:**
   ```nix
   theme = "light:stylix-light,dark:stylix-dark"
   ```
   This tells Ghostty to automatically switch themes based on the system color scheme preference.

2. **Color scheme detection:** Ghostty queries the system's color scheme preference via:
   - Reading from `org.freedesktop.appearance.color-scheme` via XDG desktop portal
   - The portal reads from dconf's `org.gnome.desktop.interface/color-scheme`

3. **Portal service failure:** The `xdg-desktop-portal-gtk` service fails at boot:
   ```
   Nov 08 08:25:09 framework .xdg-desktop-po[2795]: cannot open display:
   Nov 08 08:25:09 framework systemd[2285]: xdg-desktop-portal-gtk.service: Failed with result 'exit-code'.
   ```

### Why This Happens

1. At system boot, `xdg-desktop-portal-gtk` tries to start before the display server (Niri) is fully ready
2. The portal fails with "cannot open display" error
3. When Ghostty launches, it tries to query the portal via D-Bus
4. D-Bus attempts to auto-activate the failed portal service
5. Ghostty waits for the D-Bus timeout (~5 seconds)
6. Eventually the portal starts or Ghostty gives up and uses a default theme

### Confirmation

From systemd logs:
```bash
$ journalctl --user -u xdg-desktop-portal-gtk.service -n 50 --no-pager

Nov 08 08:25:09 framework systemd[2285]: Starting Portal service (GTK/GNOME implementation)...
Nov 08 08:25:09 framework .xdg-desktop-po[2795]: cannot open display:
Nov 08 08:25:09 framework systemd[2285]: xdg-desktop-portal-gtk.service: Failed with result 'exit-code'.
Nov 08 08:25:09 framework systemd[2285]: Failed to start Portal service (GTK/GNOME implementation).
Nov 08 08:27:13 framework systemd[2285]: Starting Portal service (GTK/GNOME implementation)...
Nov 08 08:27:13 framework systemd[2285]: Started Portal service (GTK/GNOME implementation).
```

The service eventually starts (2 minutes later), but Ghostty launched before that has to wait for timeout.

## Current Configuration

### Ghostty Theme Setup

Location: `home-manager/ghostty.nix:40-44`

```nix
programs.ghostty = {
  enable = true;
  package = pkgs.ghostty;

  # Use Ghostty's native light/dark theme switching
  # Ghostty will automatically switch based on desktop environment appearance
  settings = {
    theme = "light:stylix-light,dark:stylix-dark";
  };
};
```

This configuration requires:
- `xdg-desktop-portal-gtk` to be running
- D-Bus access to the portal
- Portal to read from dconf's `org.gnome.desktop.interface/color-scheme`

See: [`docs/stylix-darkman-setup.md`](./stylix-darkman-setup.md#8-ghostty-theme-switching-not-working) for full theme switching documentation.

## Planned Solution

**Timeline:** To be implemented when replacing DMS with ironbar

### Approach

1. **Replace DMS with ironbar** for status bar functionality
2. **Remove xdg-desktop-portal-gtk dependency** for theme switching
3. **Rely fully on Stylix and darkman** for theme management:
   - Darkman scripts activate home-manager specialisations (already working)
   - Specialisations update Ghostty config files (already working)
   - Remove portal dependency from Ghostty configuration

### Why This Works

Currently, we use the portal because Ghostty's native `theme = "light:...,dark:..."` syntax requires it to detect the system color preference. Once we remove DMS and simplify the theming setup, we can:

- Option A: Configure Ghostty to use a single theme that matches the specialisation
- Option B: Keep both themes but trigger Ghostty reload differently
- Option C: Use home-manager activation hooks to restart Ghostty instances

This will be decided during the ironbar migration.

## Temporary Workaround (Optional)

If the 5-second delay becomes too annoying before the ironbar migration, you can temporarily use a fixed theme:

### Option 1: Fixed Dark Theme

Edit `home-manager/ghostty.nix:40-44`:
```nix
settings = {
  theme = "stylix-dark";
};
```

### Option 2: Fixed Light Theme

Edit `home-manager/ghostty.nix:40-44`:
```nix
settings = {
  theme = "stylix-light";
};
```

**Note:** This removes automatic theme switching but eliminates the startup delay.

To re-enable automatic switching, revert to:
```nix
settings = {
  theme = "light:stylix-light,dark:stylix-dark";
};
```

## Technical Details

### Portal Architecture

```
Ghostty
  ↓ (queries via D-Bus)
XDG Desktop Portal (freedesktop API)
  ↓ (backend implementation)
xdg-desktop-portal-gtk
  ↓ (reads settings)
dconf: /org/gnome/desktop/interface/color-scheme
  ↑ (written by)
Darkman scripts
```

### Boot Sequence Issue

```
1. systemd starts user services
2. xdg-desktop-portal-gtk.service starts
3. Portal tries to connect to display
4. Display server (Niri) not ready yet → FAIL
5. Portal marked as failed, systemd won't auto-restart
6. User session fully starts, Niri running
7. User launches Ghostty
8. Ghostty queries portal via D-Bus
9. D-Bus tries to activate portal (retry)
10. Timeout (~5 seconds) → Ghostty finally appears
```

### Why Not Fix the Portal?

We could fix the portal startup order with systemd dependencies, but:

1. **Temporary solution:** We're planning to remove the portal dependency anyway
2. **Complexity:** Adding proper systemd ordering is complex and fragile
3. **Better architecture:** The planned solution (ironbar + darkman) is cleaner
4. **No other issues:** The portal eventually starts and works fine after boot

## Related Documentation

- [Stylix & Darkman Setup](./stylix-darkman-setup.md) - Complete theme switching documentation
- [DMS Audio Issue](./dms-audio-issue.md) - DMS-related problems (to be replaced with ironbar)

## Investigation Log

```bash
# Confirmed Ghostty binary is fast
$ time ghostty --help > /dev/null 2>&1
0.02s user 0.02s system 94% cpu 0.038 total

# Checked Ghostty version
$ ghostty --version
Ghostty 1.2.3

# Current color scheme setting
$ dconf read /org/gnome/desktop/interface/color-scheme
'prefer-dark'

# Portal service status
$ systemctl --user status xdg-desktop-portal-gtk.service
● xdg-desktop-portal-gtk.service - Portal service (GTK/GNOME implementation)
     Active: active (running) since Sat 2025-11-08 08:27:13 CET; 1min 18s ago

# Boot failure logs
$ journalctl --user -u xdg-desktop-portal-gtk.service -n 50 --no-pager
Nov 08 08:25:09 framework .xdg-desktop-po[2795]: cannot open display:
Nov 08 08:25:09 framework systemd[2285]: xdg-desktop-portal-gtk.service: Failed with result 'exit-code'.
```

**Date:** 2025-11-08
**Investigated by:** Claude Code
**Status:** Documented, awaiting ironbar migration
