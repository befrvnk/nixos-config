# Noctalia V5 on Niri

The Framework uses the native C++ **Noctalia 5.3.0** release, pinned by tag and
`flake.lock`. This is not Noctalia V4 or a Quickshell configuration.

## Ownership and layout

`home-manager/nixos/noctalia/default.nix` imports upstream's Home Manager module.
It installs `noctalia.service`, generates `~/.config/noctalia/config.toml`, and
validates the TOML with the packaged `noctalia config validate` during builds.

The initial layout uses built-in widgets, not a new home-grown shell:

- Start: CPU usage, RAM percentage, CPU temperature.
- Center: weather, date/time (the alignment anchor).
- End: app tray, notifications, network next to Bluetooth, volume, brightness,
  battery and control center.
- Transparent bar with individual bordered capsules, neutral foregrounds,
  JetBrainsMono Nerd Font and Catppuccin Mocha/Latte from `shared/themes.nix`.

Noctalia owns notifications; the dunst module is no longer imported. Historical
dunst history is not imported into Noctalia. Notifications sent through the
standard freedesktop interface continue to work.

Existing managers remain responsible for:

- Vicinae launcher and its keybinding.
- awww wallpaper and Darkman scheduling/GTK themes.
- SwayOSD and the existing audio/brightness keys, including Framework sink init.
- swaylock, idle/audio-inhibit services and the existing polkit agent.
- Gammastep, tuned Framework profiles and battery alerts.
- udiskie removable-drive mounting.

Noctalia's competing wallpaper, dock, clipboard history, screen lock, idle actions,
nightlight, polkit agent, volume/brightness OSD and low-battery alerts are disabled.
Do not enable competing owners in Settings without disabling their existing service.

## Overview-only behavior

Noctalia V5 smart auto-hide also shows on empty workspaces; that is not strict
overview-only. `overview.py` subscribes directly to Niri's event socket and calls:

- `noctalia msg bar-show` when overview opens.
- `noctalia msg panel-close`, then `bar-hide`, when overview closes.

The shell startup hook restarts `noctalia-overview.service` after IPC is ready.
The watcher initially hides the bar, then consumes Niri's initial overview state.
Duplicate events are ignored; stream/IPC failure exits so systemd reconnects.
The bar reserves no space. There may be a brief startup reveal before the hook
hides it. Reopening shell Settings outside overview is still possible via IPC.

Darkman restarts Noctalia after activating its light/dark Home Manager
specialisation, so the palette/mode and overview watcher are resynchronised.

## Settings and plugins

Open the control center's Settings UI, or run:

```sh
noctalia msg settings-toggle
noctalia msg plugins list
```

Upstream's official and community plugin sources are available. No third-party
plugin is automatically trusted/enabled in this config. Plugin auto-update is
set to `none`; update selected sources deliberately in Settings.

**V5 plugins are Luau (`plugin.toml` + `.luau`), not V4 QML plugins.** Some community
plugins still target V4. Check compatibility and review a plugin before enabling
it; being listed in a source does not guarantee V5 support.

GUI settings are stored in `~/.local/state/noctalia/settings.toml` and override the
Nix-generated config. If a rebuild appears not to affect a setting, inspect that
file. Do not delete it blindly: it also contains intentional GUI choices.

### Not yet ported

OpenRouter, aurora, firewall summary, removable-storage buttons, automatic
peripheral-battery enumeration, and the custom AMD ABM/stay-on controls are not
in this initial built-in layout. Their old source/config remains intact in
`home-manager/nixos/quickshell/` and `ironbar/`; it does not run or consume memory.
Prefer compatible V5 plugins for these before writing replacements. No Go rewrite
or QML-plugin compatibility is assumed. Noctalia's battery widget supports explicit
UPower selectors for peripherals, configurable in Settings.

## Build and validate

```sh
nix build --accept-flake-config .#nixosConfigurations.framework.config.home-manager.users.frank.programs.noctalia.package
nix build --accept-flake-config '.#nixosConfigurations.framework.config.home-manager.users.frank.xdg.configFile."noctalia/config.toml".source'
nix shell --accept-flake-config nixpkgs#python3 --command python3 -B -m unittest discover -s home-manager/nixos/noctalia -p 'test_*.py'
```

The official Noctalia cache/key are registered in `flake.nix` and `shared/caches.nix`.
Its own nixpkgs pin is retained for upstream cache compatibility. V5 may still
compile locally on a cache miss.

Verification performed before activation:

- Native package built successfully and reports `noctalia v5.3.0 (a33122c)`.
- Generated configuration passes Noctalia's own validator without warnings.
- Four overview-bridge unit tests pass (also exposed as `checks.x86_64-linux.noctalia-overview`).
- Full Framework system toplevel built successfully, including light/dark generations.
- Nix formatting and targeted statix checks pass.
- User activated the configuration and reported that Noctalia works well in an initial
  live smoke test. Extended suspend/resume, multi-monitor and plugin checks remain.

Activation is manual:

```sh
rebuild switch
systemctl --user status noctalia noctalia-overview
journalctl --user -u noctalia -u noctalia-overview -n 80 --no-pager
```

Verify overview transitions, multiple monitors, right-edge popups, notification
history, tray actions, WiFi/Bluetooth, audio and theme transitions. Do not run
`sudo systemctl --user`; root has a different user bus.

## Rollback

The previous custom shell and its flake inputs are retained for rollback but not
imported. To restore it, replace `./noctalia` with `./quickshell` and restore
`./dunst.nix` in `home-manager/nixos/frank.nix`, then restore Darkman's shell restart
target and rebuild. Never run both shells/notification daemons together.

## References

- https://github.com/noctalia-dev/noctalia/tree/v5.3.0
- https://docs.noctalia.dev/noctalia/getting-started/nixos/
- https://docs.noctalia.dev/noctalia/compositor-settings/niri/
- https://docs.noctalia.dev/noctalia/plugins/
