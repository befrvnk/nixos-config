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
  Bluetooth, volume, brightness, Caffeine, Lid Guard, battery and control center.
- Transparent bar with individual bordered capsules, neutral foregrounds,
  JetBrainsMono Nerd Font and Noctalia's built-in Catppuccin Mocha/Latte palette.

Noctalia owns notifications; the dunst module is no longer imported. Historical
dunst history is not imported into Noctalia. Notifications sent through the
standard freedesktop interface continue to work.

Existing managers remain responsible for:

- Vicinae launcher and its keybinding.
- awww wallpaper surfaces, with mode/refresh requests now driven by Noctalia.
- SwayOSD and the existing audio/brightness keys, including Framework sink init.
- swaylock, idle/audio-inhibit services and the existing polkit agent.
- Gammastep and tuned Framework profiles.
- udiskie removable-drive mounting.

Noctalia's competing wallpaper, dock, clipboard history, screen lock, idle actions,
nightlight, polkit agent and volume/brightness OSD are disabled.
Do not enable competing owners in Settings without disabling their existing service.

## Native battery warnings

Noctalia owns system-battery warnings with a 20% low threshold and native critical
escalation at 5% and 2%. Deployment has been verified and accepted; actual low-charge
alerts remain for observation during normal use. `./battery-notifications` is
no longer imported, so the custom persistent monitor is no longer installed or running. Its source
remains for rollback; do not enable both producers at once.

The old full-charge toast is not retained by default. No replacement polling code
or hook is introduced. The bar's neutral low-charge color setting is unchanged.

After rebuilding, confirm `battery-notifications.service` is inactive/not found and
`noctalia.service` is active. If already below the threshold, native warnings may
appear on startup; otherwise observe them during normal battery use. Check history
and duplicate behavior, but do not deliberately discharge to 2% for this test.

Rollback requires both restoring the old import and disabling native warnings
(`battery.warning_threshold = 0`).

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

Noctalia chooses runtime mode and uses its built-in `Catppuccin` palette. Mode
changes must not restart the shell or overview watcher. The temporary app-theme
adapter described below preserves existing application configurations.

## Settings and plugins

Open the control center's Settings UI, or run:

```sh
noctalia msg settings-toggle
noctalia msg plugins list
```

The enabled third-party plugins are pinned **Udiskie Manager** (`aristides/udiskie`)
and the **Lid Guard** trial (`8bury/lid-guard`). `plugins.nix` exports only those two
reviewed directories from `inputs.noctalia-community-plugins` as the `nix-reviewed`
path source. The mutable upstream community source is disabled to avoid duplicates;
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
- Native plugin lint and upstream translation tests run in `plugins.nix` while building the curated source.
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

### Lid Guard

The shield pill beside Caffeine runs the pinned `8bury/lid-guard` plugin (API 3).
It starts **off** unless its transient unit was already running. Loading the plugin
alone does not block lid handling. Toggle the shield to start
`noctalia-lid-guard.service`, which holds a `handle-lid-switch` block inhibitor.

This inhibits **lid events only**. Caffeine inhibits idle; enable both for the
proposed manual keep-working-with-the-lid-closed mode. No global logind setting,
swayidle/swaylock, or audio-inhibit service was removed or changed for this trial.

After rebuilding, save work, pause audio and test while undocked:

1. Toggle the shield on; inspect `systemd-inhibit --list --no-pager` for a
   `Noctalia Lid Guard` / `handle-lid-switch` / `block` entry.
2. Briefly close/open the lid to isolate lid behavior (idle timers remain active
   if Caffeine is off). Keep the laptop ventilated; never test in a bag.
3. Enable Caffeine too, close overview and check that the combined mode prevents
   both inactivity actions and lid-close suspend. Repeat on AC/battery as needed.
4. Turn the shield off and confirm its inhibitor disappears and ordinary undocked
   lid handling returns. Test intentional suspend separately when safe.

The audited `safe-suspend` helper now reads logind's structured inhibitor data.
Real `sleep` blocks still prevent it; idle/lid-only locks do not. It fails closed
if the query cannot be read/parsed, and it never bypasses logind's own policy or
screen-lock delay. Its 11 tests use fake commands and never suspend the host.

The transient Lid Guard unit can survive a shell restart or plugin disable.
Emergency/off cleanup (no sudo):

```sh
systemctl --user stop noctalia-lid-guard.service
```

The user tested the live Lid Guard integration and confirmed it works. The full
AC/battery, docked/undocked and manual-suspend matrix remains a regression checklist;
it is not individually claimed as tested. Neither lid toggles nor suspend were
triggered by the agent.

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

## Palette warning checkpoint

The old generated `Stylix.json` supplied UI colors but omitted terminal colors.
Noctalia 5.3.0's runtime palette loader requires the `terminal` object in each mode,
so it rejected the existing JSON and fell back to its default palette. Passing
`config validate` did not prove that this separate runtime palette file was valid.

The accepted fix selects `theme.source = "builtin"`, `theme.builtin = "Catppuccin"`
and removes the incomplete custom palette generator. The pinned binary ships valid
Mocha/Latte variants, including terminal colors. That palette-only fix was accepted
before preparing the runtime-controller handover below.

After the user's rebuild, current-process logs had no palette/theme warning, the
old JSON was no longer installed, and the user confirmed the Catppuccin appearance.
Historical palette warnings may still appear when querying older journal entries.

## Runtime theme-controller handover

`theme.nix` makes Noctalia the controller: `theme.mode = "auto"` uses the configured
location's sunrise/sunset; the shell follows that mode and Noctalia synchronizes the
system light/dark preference. Manual choices in Settings/Control Center or IPC take
precedence as GUI overrides and persist. Noctalia must not be restarted to switch modes.

```sh
noctalia msg theme-mode-set dark
noctalia msg theme-mode-set light
noctalia msg theme-mode-set auto
```

For this compatibility phase, the chosen mode still selects the **prebuilt** Stylix
Home Manager light/dark application theme. Noctalia owns the choice; Stylix is only
the temporary config generator. Arbitrary shell palettes do not yet recolor every app.
Per-app templates will replace that dependency one application at a time.

Noctalia's mode hook submits an atomic request. `noctalia-theme.path` starts a
serialized oneshot `noctalia-theme.service` to apply it. The worker queries the
resolved mode, waits for ordinary HM activation, uses a shared linking lock and
suppresses its own activation hooks. It then refreshes SwayOSD/Vicinae, the existing
Nushell theme state and awww. Duplicate events skip activation; newer events and
failed work remain pending. It never runs a Nix build, changes Noctalia's mode,
writes a reverse portal preference, or restarts Noctalia. After app activation it
asks Noctalia to run `templates-apply`, letting the native pipeline reassert the
owned preference (also needed after removing the old HM-managed dconf key).

Stylix's GNOME target is disabled because it otherwise overwrites the preference
with `default` in light generations. Its Noto/monospace app-font defaults are
preserved explicitly; GTK app themes and other Stylix targets remain in place.
The theme invariant check rejects any managed color-scheme key in either variant.

Ordinary rebuilds request reapplication after linking. The awww monitor-hotplug
watcher submits refresh-only requests; it no longer queries Darkman. Darkman is
not imported at either system or HM level; its old files are rollback material.
The normal HM activation hook also stops a remaining legacy Darkman user daemon.

After rebuilding, test dark then light **one at a time**, allowing the compatibility
job to finish between changes. Verify GTK apps, Niri colors, Vicinae, SwayOSD,
Nushell, Ghostty's system appearance and wallpaper. The Noctalia PID should stay
unchanged during these toggles. Return to auto mode if scheduled switching is wanted.

```sh
systemctl --user status noctalia-theme.path
journalctl --user -u noctalia-theme.service -n 80 --no-pager
systemctl --user status darkman.service
```

The path unit should be waiting; its worker is normally **inactive after success**,
not continuously running. Darkman should be inactive/not found. On failure, the
request remains under `$XDG_RUNTIME_DIR/noctalia-theme/` and the service retries.
Applied compatibility state is under `~/.local/state/noctalia/theme-bridge.json`.
The shared activation lock and recursion flag are deliberate; do not bypass them.

A pre-handover GUI-settings backup is at
`~/.local/state/noctalia/settings.pre-theme-controller.toml`. No GUI keys were deleted
for this change. Do not restore the whole file blindly or lose newer plugin/UI choices.
Before this handover, checkpoint `3f51f68` retained the old Darkman controller;
rolling back also requires reconciling any subsequently saved `theme.mode` override.

Build validation includes 14 mocked bridge tests, 4 overview tests, 11 safe-suspend
tests and `checks.x86_64-linux.noctalia-theme-invariants`. The latter verifies identical
shell/bridge service definitions across theme generations to prevent restart loops.
The deployed handover is accepted: Darkman is inactive/not found, the preference
matches Noctalia's resolved mode, and the user confirmed dark/light switching works.
Noctalia kept PID 243684 across the manual toggle trial; the worker completed
successfully with no pending request. Automatic schedule boundaries, hotplug and
suspend/resume remain regression checks. The agent did not activate generations
or switch the user's current mode.

## Consolidation plan

The next steps are documented in [Noctalia consolidation research and plan](./noctalia-consolidation-plan.md):
peripheral batteries, storage, separate Caffeine/lid controls, native battery alerts,
and moving runtime theme control from Darkman to Noctalia. OpenRouter and firewall
summary widgets are no longer required. Headphone battery visibility has been accepted;
the storage trial has passed its basic live test. Native Caffeine passed its inhibitor
and idle tests, and the Lid Guard trial is accepted. Native battery warnings are
accepted after deployment checks. The palette-warning fix is accepted; the runtime
controller handover has passed its basic live tests. Per-app template migration is next.

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

Checkpoint `3f51f68` is the accepted Noctalia palette configuration before the
runtime-controller handover. To roll back that handover, restore the controller's
system/HM imports, remove its path/worker/hooks, and reconcile only relevant saved
`theme.mode` overrides. Keep newer plugin/UI choices rather than overwriting all state.

The older custom shell and flake inputs are also retained but not imported. Restoring
that shell requires replacing `./noctalia` with `./quickshell`, restoring `./dunst.nix`
and deliberately choosing/restoring its theme controller (including both Darkman
imports if using the old setup). Never run both shells/notification daemons together.

## References

- https://github.com/noctalia-dev/noctalia/tree/v5.3.0
- https://docs.noctalia.dev/noctalia/getting-started/nixos/
- https://docs.noctalia.dev/noctalia/compositor-settings/niri/
- https://docs.noctalia.dev/noctalia/plugins/
