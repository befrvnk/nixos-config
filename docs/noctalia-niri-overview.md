# Noctalia V5 on Niri

The Framework uses the native C++ **Noctalia 5.3.0** release, pinned by tag and
`flake.lock`. This is not Noctalia V4 or a Quickshell configuration.

## Ownership and layout

`home-manager/nixos/noctalia/default.nix` imports upstream's Home Manager module.
It installs `noctalia.service`, generates `~/.config/noctalia/config.toml`, and
validates the TOML with the packaged `noctalia config validate` during builds.

The layout uses built-in widgets plus one reviewed storage plugin, not a new home-grown shell:

- Start: CPU usage, RAM percentage, CPU temperature.
- Center: weather, date/time (the alignment anchor).
- End: app tray, storage (when a device is present), notifications, network next to
  Bluetooth, volume, brightness, Caffeine, battery and control center.
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

The only enabled third-party plugin is the pinned **Udiskie Manager** storage trial
(`aristides/udiskie`). Its source is the `nix-reviewed` path source; only the reviewed
plugin directory is exported from `inputs.noctalia-community-plugins`. The mutable
upstream community source is disabled to avoid duplicate copies of the same plugin;
the official source remains available. Plugin auto-update stays set to `none`.

**V5 plugins are Luau (`plugin.toml` + `.luau`), not V4 QML plugins.** Some community
plugins still target V4. Check compatibility and review a plugin before enabling
it; being listed in a source does not guarantee V5 support.

GUI settings are stored in `~/.local/state/noctalia/settings.toml` and override the
Nix-generated config. If a rebuild appears not to affect a setting, inspect that
file. Do not delete it blindly: it also contains intentional GUI choices.

### Removable storage

Configured in `home-manager/nixos/noctalia/storage.nix`; user tested the live integration
and confirmed it works:

- Udiskie Manager `0.1.0`, API 9, pinned source `bd834815ee5da2ed744a9cbf1425342a4eecba6f`.
- Native plugin lint and upstream translation tests run while building the curated source.
- `storage` bar widget uses `aristides/udiskie:status`, with device count and hide-when-empty.
- Plugin notifications and automatic file-manager opening are off. The existing udiskie
  daemon still handles automount and notifications; it has not been replaced.
- Noctalia's service PATH explicitly includes its own CLI, udiskie, UDisks tools,
  xdg-open, bash and coreutils, plus existing user/system paths.

After rebuilding, insert a disposable USB/SD device and check automount, opening,
unmount/eject, reinsertion, and absence of duplicate notifications. Never test bulk
unmount/eject on real work volumes. The widget is intentionally hidden with no devices.
You can open the panel directly with:

```sh
noctalia msg panel-toggle aristides/udiskie:manager
```

To roll back the trial at runtime, disable the plugin in Settings (or
`noctalia msg plugins disable aristides/udiskie`). This creates a GUI override;
re-enabling declaratively later requires reconciling that specific override.
The udiskie automounter continues to work independently.

### Not yet ported

OpenRouter, aurora, firewall summary and custom AMD ABM/stay-on controls are not
in the active layout. OpenRouter/firewall summary are no longer requirements. Their old source/config remains intact in
`home-manager/nixos/quickshell/` and `ironbar/`; it does not run or consume memory.
Prefer compatible V5 plugins for these before writing replacements. No Go rewrite
or QML-plugin compatibility is assumed. Noctalia's battery widget supports explicit
UPower selectors for peripherals, configurable in Settings. Native headphone battery
reporting has been confirmed by the user; no additional battery plugin is needed.

### Native Caffeine

The built-in `caffeine` pill beside brightness/battery toggles Noctalia's idle
inhibitor. It is not automatically enabled. The existing swayidle/swaylock and
`audio-idle-inhibit` services remain active; no lid policy has changed.

After rebuilding, pause audio and check that no other stay-awake inhibitor masks
this test. Enable Caffeine and inspect `systemd-inhibit --list --no-pager`.
On the normal logind backend, expect a Noctalia `idle` block inhibitor. Close
overview and confirm the usual 300/305/310-second lock/monitor-off/suspend chain
stays inactive. Save work first in case the test exposes an integration gap.
Disable Caffeine and verify the ordinary idle behavior returns.

The user confirmed the inhibitor appears and the laptop stays awake during the idle
trial. Caffeine does not request a lid-close blocker; that is a separate feature.
Off/release and suspend/resume behavior remain useful regression checks.

## Consolidation plan

The next steps are documented in [Noctalia consolidation research and plan](./noctalia-consolidation-plan.md):
peripheral batteries, storage, separate Caffeine/lid controls, native battery alerts,
and moving runtime theme control from Darkman to Noctalia. OpenRouter and firewall
summary widgets are no longer required. Headphone battery visibility has been accepted;
the storage trial has passed its basic live test. Native Caffeine passed its inhibitor
and idle tests; Lid Guard, notification and theme changes are next.

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
