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
- Prepared shared continuous floating bar: one Surface-role background, 16px top/
  side gap, neutral foregrounds, JetBrainsMono Nerd Font and Catppuccin Mocha/Latte.
  This replaces individual widget islands; [visual/edge-slide acceptance is pending](noctalia-topbar.md).

Noctalia owns notifications; the legacy dunst module was removed. Historical
dunst history is not imported into Noctalia. Notifications sent through the
standard freedesktop interface continue to work.

Existing managers remain responsible for:

- Vicinae launcher and its keybinding.
- Existing brightnessctl/DDC synchronization and Framework audio sink initialization.
  Noctalia now owns the prepared output-volume/brightness OSD and volume-key IPC.
- swaylock, idle/audio-inhibit services and the existing polkit agent.
- Gammastep and tuned Framework profiles.
- udiskie removable-drive mounting.

Noctalia's dock, clipboard history, nightlight and polkit agent are disabled.
Native screen locking/idle and output-volume/brightness OSD are enabled in the
current migration; microphone/lock-key OSD remain off. Fallback auth remains installed.
Do not enable competing owners in Settings without disabling their existing service.

## Overview watcher lifecycle

`noctalia-overview.service` is wanted by the graphical session, ordered after
both `graphical-session.target` and Noctalia, and stopped with Noctalia. The
explicit target ordering is required: systemd implicitly orders a target after
units that are `WantedBy=` it but lack explicit ordering relative to it. Relying
only on `After=noctalia.service` therefore built a cycle (target → Noctalia →
watcher → target) that systemd resolved by dropping `noctalia.service` on some
boots, leaving a wallpaper-less grey session without bar or shell keybind
helpers. The native `started` hook restarts the watcher once IPC is ready. Home
Manager also idempotently starts the watcher after reloadSystemd.
This second path is necessary: unit reconciliation can stop a PartOf dependent
while a concurrent job cancels the shell's own restart. The shell stays alive,
its started hook never runs, and an otherwise healthy overview-only bar stays hidden.

The prepared [Umbriel trial](umbriel-trial.md) extends this same watcher to the
active compositor's event protocol, selected by desktop identity and its own socket.
Niri EventStream behavior remains; Umbriel subscribes to overview with an initial
snapshot. Wayland plus either compositor socket gates the unit. This is not a bar
redesign or live Umbriel acceptance; Niri remains the default/recovery session.

The GTK-stage rebuild exposed this on 2026-10-20. Starting only the watcher restored
its event subscription without restarting Noctalia or changing bar appearance.
Flake invariants now enforce session enablement, post-reconciliation recovery and
identical watcher units across app-theme variants. The permanent fix awaits rebuild.

## Native battery warnings

Noctalia owns system-battery warnings with a 20% low threshold and native critical
escalation at 5% and 2%. Deployment has been verified and accepted; actual low-charge
alerts remain for observation during normal use. `./battery-notifications` is
no longer imported, so the custom persistent monitor is no longer installed or running. Its source
remains for rollback; do not enable both producers at once.

Stock v5.3.0 repeated the low-battery toast in two ways: every shell restart re-fired
whatever level the battery already sat in, and its "re-arm while charging" step meant
any flap of the battery's own charge state (the Framework EC reports `discharging` or
`unknown` while AC is connected) fired the warning again with the charger plugged in.
`noctalia/battery-warning-no-spam.patch` fixes both: charging or an ambiguous charge
state only *suppresses* warnings without re-arming the level, the system battery also
requires UPower's aggregate `OnBattery` (the AC-online signal that does not flap), and
the startup pass records the configured low level silently while still escalating the
critical 5%/2% levels immediately. Re-arming happens solely when the charge rises past
every alert point, so a real recharge/discharge cycle still warns again.

`checks.<system>.noctalia-battery-warning` applies the full patch set with `--fuzz=0`
and drives the patched monitor through those flap/restart sequences (`test_battery_warning.cpp`;
the sdbus-backed UPower header is mirrored in `battery-warning-stubs/`). It fails against
stock v5.3.0 and must stay green after Noctalia input bumps.

The old full-charge toast is not retained by default. No replacement polling code
or hook is introduced. The bar's neutral low-charge color setting is unchanged.

After rebuilding, confirm `battery-notifications.service` is inactive/not found and
`noctalia.service` is active. If already below the threshold *and* charging has not
started, the critical 5%/2% levels may still notify on startup; the 20% level is
intentionally not repeated after a restart. Otherwise observe warnings during normal
battery use. Check history and duplicate behavior, but do not deliberately discharge
to 2% for this test.

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
in the active layout. OpenRouter/firewall summary are no longer requirements. The
retired Quickshell/Ironbar implementation was removed; prefer compatible V5 plugins
for these before writing replacements. No Go rewrite
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
serialized finite `noctalia-theme.service` to apply it. It uses `Type=exec` so
startup readiness does not wait for the worker's activation work to finish. The worker queries the
resolved mode, waits for ordinary HM activation, uses a shared linking lock and
suppresses its own activation hooks. It then requests native app-template refresh;
native wallpaper hooks now own image selection independently.
Nushell's runtime data is now written only by Noctalia's native template renderer. Duplicate events skip activation; newer events and
failed work remain pending. It never runs a Nix build, changes Noctalia's mode,
writes a reverse portal preference, or restarts Noctalia. After app activation it
asks Noctalia to run `templates-apply`, letting the native pipeline reassert the
owned preference (also needed after removing the old HM-managed dconf key).

Stylix's GNOME target is disabled because it otherwise overwrites the preference
with `default` in light generations. Its Noto/monospace app-font defaults are
preserved explicitly; GTK app themes and other Stylix targets remain in place.
The theme invariant check rejects any managed color-scheme key in either variant.

Ordinary rebuilds request reapplication after linking. Native Noctalia now owns
wallpaper output/hotplug handling; the custom monitor-hotplug watcher is removed. Darkman is
not imported at either system or HM level; its old files are rollback material.
The normal HM activation hook also stops a remaining legacy Darkman user daemon.

After rebuilding, test dark then light **one at a time**, allowing the compatibility
job to finish between changes. Verify GTK apps, Niri colors, Vicinae, SwayOSD,
Nushell, Ghostty's system appearance and wallpaper. The Noctalia PID should stay
unchanged during these toggles. Return to auto mode if scheduled switching is wanted.

```sh
systemctl --user status noctalia-theme.path
journalctl --user -u noctalia-theme.service -n 80 --no-pager
systemctl --user status noctalia.service
```

The path unit should be waiting; its worker is normally **inactive after success**,
not continuously running. The retired Darkman service must not exist. On failure, the
request remains under `$XDG_RUNTIME_DIR/noctalia-theme/` and the service retries.
Applied compatibility state is under `~/.local/state/noctalia/theme-bridge.json`.
The shared activation lock and recursion flag are deliberate; do not bypass them.
The canonical lock is now under the configured state home at
`noctalia/theme-activation.lock`, so it is available before login. With a runtime
directory available, both callers additionally retain the old runtime activation
lock for compatibility with older generations; state is always locked first.

A pre-handover GUI-settings backup is at
`~/.local/state/noctalia/settings.pre-theme-controller.toml`. No GUI keys were deleted
for this change. Do not restore the whole file blindly or lose newer plugin/UI choices.
Before this handover, checkpoint `77d6c20` (originally `3f51f68`) retained the old Darkman controller;
rolling back also requires reconciling any subsequently saved `theme.mode` override.

Build validation includes 25 mocked bridge tests, 10 isolated activation/overview/
request-hook and service-readiness contract tests, 2 real isolated Atuin/Nu integration-warning probes,
4 overview tests, 10 Ghostty
integration/migration tests, 6 GTK tests, 4 Qt tests (with real offscreen Qt5/Qt6 probes),
6 Vicinae tests (with its actual pinned theme parser), 6 Zed tests (including the actual
Home Manager settings merger), 7 Zen tests (including actual packaged policy checks),
6 VS Code tests (including isolated CLI extension discovery), 6 lazygit tests
(including real isolated PTY/color checks), 7 fzf tests (real Nu/selectors/PTYs),
7 Niri template tests (full KDL validation, colors and backdrop-only placement), 6 Nushell tests
(real Nu rendering/reader/hook checks), 6 Starship tests (real CLI/prompt RGB),
8 native OSD/control tests (all hardware mocked), 6 btop tests (including isolated native reload),
6 plain-Emacs tests (real batch theme/init loading), 6 Xresources tests (real isolated Xvfb/xrdb),
6 GTKSourceView tests (real headless version 4/5 style-manager loading),
8 native lock/idle policy and native-parser probes (no authentication/session actions),
19 safe-suspend tests (all system commands mocked) and
`checks.x86_64-linux.noctalia-theme-invariants`. The latter verifies identical
shell/bridge service definitions across theme generations to prevent restart loops;
it is also exposed as `checks.x86_64-linux.noctalia-theme-<name>` so a failure names
the affected app (config, ghostty, gtk, qt, vicinae, zed, zen, vscode, niri, nushell,
wallpaper, and so on).
The deployed handover is accepted: Darkman is inactive/not found, the preference
matches Noctalia's resolved mode, and the user confirmed dark/light switching works.
Noctalia kept PID 243684 across the manual toggle trial; the worker completed
successfully with no pending request. Automatic schedule boundaries, hotplug and
suspend/resume remain regression checks. The agent did not activate generations
or switch the user's current mode.

## Ghostty built-in template integration

`home-manager/nixos/ghostty.nix` now fixes `theme = noctalia` in the declarative main
config and preserves the existing Shift+Enter keybinding. `noctalia/ghostty.nix`
enables the shipped built-in `ghostty` template, not a community/user replacement.
It renders a separate writable `~/.config/ghostty/themes/noctalia` and runs upstream's
apply/reload hook. That hook skips main-config writes when the fixed reference exists.

The old custom color generator and `stylix-light`/`stylix-dark` files are removed.
Noctalia owns Ghostty's runtime palette, not merely its light/dark choice. Other apps
still use the compatibility path until individually migrated.

An activation-only helper prepares the output before linking configs. It backs up
legacy read-only contents once to `~/.local/state/noctalia/ghostty-theme.pre-template`,
then makes only the user-facing file a private writable copy. Link targets/Nix-store
files are never modified. Already writable runtime output is left alone, preserving
colors during future HM specialisation activations. New installs get a valid
comment-only placeholder until Noctalia generates colors.

After rebuilding, verify:

- `~/.config/ghostty/config` remains a Home Manager symlink containing `theme = noctalia`.
- `themes/noctalia` is a regular writable file, generated by Noctalia.
- Native template logs have no permission errors; the old static theme links are gone.
- Already-open terminals update on a Noctalia dark/light toggle; no restart is needed.
- Shift+Enter still behaves as configured. No other terminal settings were migrated.

The 10 integration/migration tests use temporary files, offline template rendering
and a fake reload script; they never signal a running terminal. Build/config checks
passed, and the user confirmed live palette propagation after rebuilding. Dark/light
mode switching was already supported before; changing the actual Noctalia palette
now changes Ghostty rather than leaving it on the old fixed Catppuccin colors.
Deployment inspection confirmed the protected config symlink, writable private theme,
secure backup and removal of the old static theme links.

## GTK3/GTK4 built-in templates (checkpoint approved)

`noctalia/gtk.nix` enables the stock `gtk3`/`gtk4` templates alongside Ghostty. Both
Nix-managed `gtk.css` files contain `@import url("noctalia.css");`. The pinned apply
hook detects that literal import and leaves the symlinks alone. Each template writes
only its separate `gtk-3.0/noctalia.css` or `gtk-4.0/noctalia.css` runtime output.
The shared `prepare_theme_output.py` seeds both outputs with valid CSS comments before
linkGeneration, handles protected legacy files with backups, and leaves existing
writable colors alone during later compatibility activations.

The Stylix GTK target is disabled: no fixed generated CSS and no managed `gtk-theme`
dconf preference. Noto Sans 11, Papirus icons, Quintom_Snow/24 and adw-gtk3 remain.
GTK4 stays on libadwaita. The stock hook chooses adw-gtk3/adw-gtk3-dark through
settings tools; the existing Noctalia path still owns the color-scheme preference.

This also removes Stylix's flattened `~/.themes/adw-gtk3` and its fixed Flatpak override.
Native GTK apps are this stage's scope; sandboxed apps need separate theme/access
review. Do not claim that every Flatpak app will adopt these CSS files.

After rebuilding:
- Check both `gtk.css` files remain symlinks containing only the import; both
  `noctalia.css` outputs should be private writable regular files.
- Select a different Noctalia palette, not merely dark/light mode. Compare a native
  GTK3 app and a GTK4/libadwaita app (e.g. Nautilus); then test dark/light separately.
- Check fonts, Papirus icons and the cursor are unchanged. Some GTK apps may require
  reopening for CSS changes; check fresh windows as well as existing ones.
- Inspect native template logs for errors and confirm gsettings/dconf selects
  adw-gtk3 in light mode and adw-gtk3-dark in dark mode.

Six tests exercise the pinned templates and hook with isolated XDG dirs and mocked
settings tools, including two distinct palettes in both modes. No live preference
is changed by tests. Full build/config/invariant checks pass; live acceptance is pending.
Initial live test: Files and Adwaita Bluetooth did not update while running. Both
are GTK4/libadwaita, and both processes predated the most recent rendered CSS.
The runtime CSS is generated and parses cleanly using their actual GTK 4.22.4 library,
including the managed relative import. GTK4 loads user CSS at initialization; the
shipped hook has no generic running-app CSS reload mechanism. Full quit/relaunch
with a different selected palette was the next check. User confirmed Adwaita Bluetooth
adopts the palette after restarting, but Files still does not. Both were closed at
the next process inspection; inspect a fresh Files instance's origin/environment
before assuming it is just caching. Files and GTK3 acceptance remain pending.
User approved committing this partial checkpoint and continuing; Files and GTK3 checks
are explicitly deferred. Do not treat file generation as live success.
See [GTK's CssProvider docs](https://docs.gtk.org/gtk4/class.CssProvider.html) and
[GTK's dynamic CSS reload issue](https://gitlab.gnome.org/GNOME/gtk/-/issues/3409).

Template enablement stays declarative: upstream undo hooks try to edit the entrypoint,
so rollback via Nix/rebuild rather than invoking GUI template undo on managed CSS.

## Qt built-in template (runtime palette propagation verified)

`noctalia/qt.nix` enables the shipped `qt` template. It generates separate writable
`qt5ct/colors/noctalia.conf` and `qt6ct/colors/noctalia.conf` files. Their corresponding
main configs remain Nix-managed, explicitly select the runtime palette, and keep
Noto Sans 11, JetBrainsMono Nerd Font 11 and Papirus. They moved out of `vicinae.nix`.

The style changes from Kvantum to Fusion so widgets honor QPalette colors. System
Qt still supplies both qtct plugins and the existing `QT_QPA_PLATFORMTHEME=qt5ct`;
Qt6ct advertises that alias too. Real offscreen Qt5/Qt6 tests exercise it rather than
assuming compatibility. No environment change or new service is introduced.

The common output preparer handles old read-only palettes before linkGeneration,
backing up to `~/.local/state/noctalia/qt5ct.pre-template.conf` and its Qt6 counterpart.
It leaves writable runtime colors alone on later activations and seeds new files
with an INI header until the native renderer runs. Link targets are never modified.

Four tests render the pinned template and launch isolated offscreen Qt5/Qt6 probes,
checking two distinct palettes in both modes, fonts/icons/Fusion, bootstrap and
protected legacy output. Main-config symlinks stay intact. Full build/config checks
pass. After the user's rebuild with substitutions disabled, both live configs and
writable outputs were verified, and real offscreen Qt 5.15.19/Qt 6.11.1 probes matched
the live generated colors, Fusion, fonts and Papirus without changing the managed
config symlinks. The overview watcher is active and compatibility worker successful.
The user then selected Kanagawa, still in light mode. Both Qt probes changed from
Catppuccin's window/foreground/highlight colors to Kanagawa's #f2ecbc/#545464/#c7d6b3,
matching the freshly generated palettes. Fonts, icons, Fusion and protected config
symlinks stayed intact; shell/watcher remained active. This verifies palette
propagation, not just mode switching. Already-running GUI hot reload and
app-specific visual behavior remain untested.

After rebuilding, confirm both main config symlinks and private writable palette
outputs. Test an actual Qt app that honors system palettes; reopen if needed.
The stock template has no reload hook, so do not promise universal live switching.
Apps with custom styles may ignore it. Vicinae uses a separate community template,
not the generic Qt palette; its integration is described below.

## Vicinae community template (accepted)

There is no shipped Vicinae built-in template. The reviewed community integration
is pinned at `noctalia-dev/community-templates@7aae018927ae35d007734868388c34c901870f45`.
`noctalia/vicinae.nix` registers its upstream TOML and Bash hook as a user template,
not a mutable community catalog download or custom replacement. No theme file is forked.

Both declarative Vicinae mode selectors are `noctalia`, preserving Papirus. The
existing Home Manager wrapper keeps settings in high-priority VICINAE_OVERRIDES.
The upstream hook calls `vicinae theme set noctalia`; reviewed v0.29.2 retains the
v0.23.0 behavior: it rescans and reloads the
current theme without writing settings when the selector already matches. Its
normal config-writing branch is intentionally avoided. Other launcher settings,
extensions and keybindings are unchanged. The old custom Stylix theme is removed.

Only `~/.local/share/vicinae/themes/noctalia.toml` is writable runtime output. The
shared preparer seeds a valid inherited built-in theme until rendering, privatizes
protected legacy output with a backup, and leaves writable colors alone later.
Upstream's optional icon argument copies the pinned Noctalia SVG only if absent;
existing icons are preserved. No new watcher/service/restart script is added.
The compatibility bridge no longer restarts Vicinae; native theme-set owns reload.

Six tests render two palettes in both modes and use the actual pinned theme parser/
resolver, exercise upstream hook calls with a fake CLI, and check legacy/icon/config
preservation and bootstrap. No user server is contacted by tests. A bridge regression
test forbids Vicinae restarts; config/unit invariants prevent mode-dependent restart
triggers. Full build and native validation pass. The user rebuilt and confirmed
palette propagation works. Inspection verified the writable theme, removal of the
old Stylix output and active launcher/shell/overview services. PID stability across
palette changes was not independently sampled.

A startup hook ran before Vicinae's IPC socket was ready and logged connection
refused. The generated theme was available for startup and later palette tests
worked; this remains a documented transient warning, not a persistent failure or
an error-free startup claim. No custom restart/retry daemon was added.

After rebuilding, use the normal launcher keybinding, select another Noctalia
palette and compare the launcher. It should update without a server restart or
settings write. Confirm the running PID remains stable after palette/mode changes,
the main overrides still select `noctalia`, and template/launcher logs have no errors.

Zed's subsequent integration is described below. Remaining community-template
migrations requested by the user are tracked below. Zen's safe CSS integration is
prepared; VS Code, lazygit and fzf remain. All exist in the pinned repository; review
per-app ownership/reload before enabling. The remaining three are not enabled here.

## Zed community template (accepted)

`noctalia/zed.nix` registers the pinned upstream `zed/zed.json` verbatim, producing
only `~/.config/zed/themes/noctalia.json` (not the repository's optional Gram output).
The family always contains `Noctalia Dark`, `Noctalia Light` and their transparent
variants. Declarative settings select the opaque pair with `theme.mode = system`,
so Noctalia's existing native appearance preference determines the editor mode.

Stylix's Zed target and static Base16 family are disabled. JetBrainsMono/Noto font
families and their existing 4/3 point conversion are kept explicitly. Tab-bar settings,
Nix extension and other editor preferences are unchanged. Home Manager retains its
existing mutable JSON5 merge: it owns the configured fields without discarding
unrelated user settings (including icon theme and language-server preferences).
Shared and Darwin modules are untouched; this integration is NixOS-only.

The common output preparer handles protected legacy JSON with backups and provides a
minimal empty-refinement family containing the selected names until the first render.
Already writable generated output is left alone by subsequent activations. No
Noctalia hook edits settings, invokes Zed or restarts it. The upstream template
provides no reload hook; actual live editor behavior remains for user verification.

Six tests cover two palettes/all four variants, active-mode independence, the actual
Home Manager merger on JSON5 user settings, settings untouched by template rendering,
bootstrap and protected output. These validate rendered JSON/structure, not Zed's
full schema/parser or GUI reload. Native config/invariants/lint/full build pass.
The user rebuilt and confirmed it works. Live inspection verified the system-mode
selectors, all four variants in a writable regular file, preserved font families/
sizes, removed Stylix output and active shell/overview watcher. GUI behavior is
user-confirmed, not independently instrumented by the rendering tests.

After rebuilding, open Zed and check it selects Noctalia Light/Dark through system
mode. Choose a noticeably different palette in Noctalia and compare Zed, then test
light/dark mode separately. Keep the configured system selector rather than manually
pinning a theme in Zed's picker. If it doesn't refresh while running, fully reopen
Zed once and report whether the new palette appears. No live theme has been changed
by the agent. See [Zed's theme settings](https://zed.dev/docs/themes).

## Zen Browser community CSS (accepted)

`noctalia/zen-browser.nix` registers both pinned upstream CSS templates verbatim.
The generated chrome/content files live in persistent XDG state under
`noctalia/zen-browser`, not cache storage. Nix-managed CSS entrypoints in only the
existing `.zen/default` profile import them by absolute file URI. Valid placeholders
are prepared before linkGeneration; generated output stays writable.

The upstream apply hook is deliberately not run: it scans all matching profiles,
including old/backups, writes through protected symlinks and rewrites user.js.
Instead Nix owns the imports and enables only the required stylesheet preference
through browser policy. No developer-tools preference, profile scan, prefs.js/user.js
writer or browser restart process is added. The custom Base16 generators are removed;
responsive 82px/64px new-tab logo sizing remains in a separate non-color stylesheet.

The profile-aware launcher now uses the module-configured beta package rather than
the raw flake package, ensuring the declared policies actually reach the browser.
The exact `-P "Default Profile"` behavior, desktop actions, extension declarations,
privacy and password-manager policies are retained. Shared/Darwin browser config is
unaffected. Tests inspect actual packaged policies as well as the launcher script.

Seven tests render two palettes and both modes, check import/profile boundaries,
policy/launcher preservation, non-color layout and output preparation. They do not
launch Zen or validate CSS with Gecko. Both files already include dark/light media
queries, so mode selection needn't regenerate colors, but a newly generated palette
may require fully quitting/reopening Zen. No live reload is promised. The upstream
styles have some global content accents and limited coverage of certain about pages.

After rebuilding, select a different Noctalia palette, save work and fully quit/
reopen Zen via the existing launcher. Check chrome/internal pages, profile identity,
extensions and 1Password; test light/dark separately. `about:policies` can verify the
active policies. The user rebuilt and confirmed it works. Live inspection verified
Nix-managed imports, regular writable generated CSS, active shell/overview services
and no recent renderer errors. The agent did not restart Zen or independently
instrument profile/extension behavior or live-versus-restart palette reload.
See [the browser module guide](../home-manager/nixos/zen-browser/README.md).

## VS Code community template (accepted)

`noctalia/vscode.nix` enables Home Manager's VS Code module (previously only the
package was installed, without local Code/.vscode directories). Its default profile
owns the Noctalia selector and settings; manual installation of other extensions
remains possible. The duplicate package-list entry is removed. Shared/Darwin editor
configuration is unaffected.

The official Marketplace Noctalia extension 0.0.5 is pinned by hash. Its original
manifest/icon remain immutable; only its theme JSON is replaced with a symlink to
`~/.local/state/noctalia/vscode/NoctaliaTheme-color-theme.json`. The pinned community
renderer writes that separate state file verbatim. This avoids writing through a
Nix-managed extension link or relying on the upstream versioned-directory layout.
No activation code, custom extension manifest/color theme or reload script is added.
The shared preparer handles writable bootstrap/legacy output before linkGeneration.

The dormant Stylix VS Code target/extension is disabled. Its intended static font
mapping is retained from the pinned source, with NoctaliaTheme replacing the fixed
selector. Automatic competing theme selection, editor updates and extension
updates are disabled; other extensions can still be installed/updated manually.
Settings remain Nix-managed, not editable by the template.

Upstream has one vs-dark contribution and hardcodes JSON type dark. It renders
light colors when Noctalia selects light, but VS Code still classifies it as dark;
fallback colors or extensions may reflect that limitation. It is documented, not
silently fixed by forking the community template. Native live reload is unverified.

Six tests render two palettes/both modes, check real CLI extension discovery,
metadata/link ownership, font/update settings and bootstrap. In the build sandbox
the packaged CLI script runs under Nix Bash because /usr/bin/env is unavailable.
No editor GUI/user profile is opened. Native config/lint/invariants/full build pass.
The user rebuilt and confirmed it works. Live inspection verified Nix-managed settings
and extension links, selected NoctaliaTheme 0.0.5, declared fonts and a writable 0644
runtime palette; shell/overview remain active. Exact GUI reload mechanics and light
classification behavior were not independently instrumented.

After rebuilding, open VS Code, confirm NoctaliaTheme is installed/selected, change
the Noctalia palette and test light/dark separately. Report any missing live refresh
or light-mode contrast problems; a window reload may be needed. Do not enable the
mutable community VSCode catalog entry too: it writes different versioned paths.

## lazygit community theme (accepted)

`noctalia/lazygit.nix` registers the pinned community YAML unchanged, rendering
`~/.config/lazygit/themes/noctalia.yml`. It deliberately skips the upstream apply
hook because that hook copies colors into config.yml through its Nix-store symlink.

The package wrapper supplies lazygit's native `LG_CONFIG_FILE` with base config
first, theme overlay second. This is a default, not a forced global environment:
explicit LG_CONFIG_FILE or --use-config-file can override it. Repo-local configs
retain native precedence too. No new login is required; the existing Nushell `lg`
function resolves the wrapped executable. Shared/Darwin configuration is unchanged.

Stylix's lazygit target is disabled. A managed empty gui map keeps config.yml present
when no other settings exist; user-defined non-theme settings still merge normally.
The common preparer creates a valid empty-YAML output until rendering, safely backs
up protected legacy data and preserves writable colors on later activations. No
custom color mapper, merge script, poller or restart hook is added.

Six tests render two palettes/modes and use the real lazygit binary in isolated PTYs
and temporary git repositories to observe expected RGB output and retention of a
custom base quit key. They also check explicit flag precedence, protected config,
wrapper defaults and output preparation. Only fixture repositories are initialized/
committed; no user repository or terminal is affected. GUI startup/update/fetch
settings used by tests are not applied to production config.

Full build/config/lint/invariant checks pass. The user rebuilt and confirmed it works.
Live inspection verified the managed base symlink, separate writable overlay, ordered
wrapper default and healthy shell/overview services. Exact running-TUI hot reload was
not independently instrumented.

After rebuilding, open lazygit or `lg`
in a repository and test a different Noctalia palette and light/dark separately.
If an already-running TUI doesn't update, quit/reopen it and report the distinction.
Native hot reload is not claimed from startup tests. Do not enable the community
catalog entry too: its hook would try to rewrite the managed base file.

## fzf community colors + Nushell (accepted)

The pinned community repo has Bash/Fish snippets but no Nu template. `noctalia/fzf.nix`
uses the upstream Bash input unchanged. `fzf-package.nix` sources the generated
`~/.config/fzf/themes/noctalia.sh` inside each fzf child wrapper, then execs the real
binary. The parent Nu session is not modified and needs no generated-code evaluation.
No custom theme, Fish universal variable or shell-startup hook is introduced.

`programs.fzf.enable` remains false, so existing Atuin/history/picker keybindings
are untouched. The shared package list consumes programs.fzf.package: NixOS gets the
wrapper while Darwin's package/integrations remain unchanged. The wrapper includes
the original manual pages. Only the dormant Stylix color target is disabled.

The standard output preparer creates a valid comment until the first render and
handles protected legacy snippets with a backup. XDG_CONFIG_HOME is resolved at
invocation time, with the configured fallback. Existing FZF_DEFAULT_OPTS/options
files are retained; CLI flags can still override defaults. Repeated top-level calls
do not accumulate colors in the parent shell. A newly opened picker reads the latest
palette, while an already-running picker retains its startup options.

Seven tests use two palettes/modes, native selectors, real Nu and isolated PTYs,
checking RGB output, unchanged parent options, file/CLI precedence and bootstrap.
Tests do not open a user picker or change a user shell. Full build/native config/
invariants/lint pass. After rebuilding, open a picker, change the Noctalia palette
and open a new picker to compare; test light/dark separately. Existing keybindings
should be unchanged. For a simple Nu test:

```nu
["alpha" "beta" "gamma"] | str join (char nl) | fzf
```

The user rebuilt and confirmed it works. Live inspection verified the writable
snippet and per-invocation wrapper; a filter smoke test selected the expected line,
and shell/overview services remain active. Detailed keybindings were not independently
instrumented. All requested community integrations are accepted, but this does not
finish all app migration or retire the compatibility bridge.

## Niri built-in colors (accepted)

`noctalia/niri.nix` enables the unmodified stock `niri` template and appends a
managed absolute `include ... optional=true` to niri-flake's rendered configuration.
Only `~/.config/niri/noctalia.kdl` is runtime-writable. Upstream's output hook resolves
that path; its apply hook recognizes the include and never appends through the
Home Manager config symlink. No custom color template/reload script is introduced.

Niri 26.04 merges color properties from included layout blocks without resetting
other declared settings, and watches included files for live config reload. The
main config retains 4px borders, focus ring off, 12px gaps, transparent backgrounds,
shadow/overview settings, rules, bindings, inputs/outputs and startup behavior. Only
the two fixed active/inactive Base16 colors are removed from layout.nix. The shipped
fragment also themes tab/insert/recent-window highlights without changing layout flags.

The optional include is necessary for niri-flake's build-time validator, which has
no user-home file. Activation seeds a valid comment/private output before linking.
Runtime files normally exist, so missing-file warnings aren't expected there. Invalid
included content still fails validation even with optional=true. Protected old output
is safely backed up; existing writable colors remain untouched by HM activation.

Six tests validate the complete generated config with real rendered fragments for
two palettes/both modes, exercise the pinned hook against a protected symlink, check
structure/bootstrap and reject invalid data. They do not start/reload the compositor.
Main config is identical across theme specialisations. Native config/cache/invariant/
lint/full Framework build checks pass. The user rebuilt and confirmed it works.
Live inspection verified the managed main config, writable include and active
shell/overview services; `niri validate` accepted the complete live configuration.
GUI behavior is user-confirmed rather than independently instrumented by tests.

After rebuilding, select a different Noctalia palette and check focused/inactive window
borders. Test light/dark separately; ensure border width, gaps, background transparency,
focus-ring state, bindings/window behavior and overview-only bar are unchanged. Niri
should pick up the file change without a compositor restart. See
[Niri include merging](https://niri-wm.github.io/niri/Configuration%3A-Include.html).

## Nushell native-rendered NUON (accepted)

Neither pinned template catalog contains a Nushell entry. `noctalia/nushell.nix`
registers the small local `nushell.nuon` data template with Noctalia's existing native
renderer. It maps the old color-config fields and bold attributes to terminal and
semantic tokens, rather than generating fixed Base16 variants. Output remains the
writable `$XDG_STATE_HOME/nushell/theme.nuon`. No shell code is generated/evaluated,
no post-hook or extra controller/service is introduced.

The NixOS Nushell module retains the pre-prompt reader, externalized in
`noctalia/nushell-theme.nu`. It reads on startup or changed mtime and honors XDG
state paths. Missing, empty, nonrecord or partial input preserves the last colors;
failed reads do not advance the cache, allowing the next prompt to retry. Other
prompt hooks, keybindings, completions, NixOS aliases and shared/Darwin configuration
are unchanged. The two static config theme files and env-stage dark-theme copy are
removed. The output preparer supplies `{}` until first render without clearing defaults.

The compatibility bridge no longer copies Nushell state and works without the old
files. Its current remaining explicit refreshes are SwayOSD and wallpaper; do not
remove it before reviewing every remaining specialisation consumer.

Six real-Nu tests render two palettes/modes, assign actual color_config, exercise
startup and same-session prompt updates, retained hooks/settings, cache/partial-read
recovery and protected output. A bridge regression proves it never rewrites native
NUON across mode changes. Native config/cache/invariants/lint/full build pass.
The user rebuilt and accepted the result. Live inspection verified writable data,
removed static variants, the installed reader, native NUON parsing and active shell/
overview services. Detailed integration behavior was not independently instrumented.
Tests never alter an active user shell.

After rebuilding, open one fresh Nu session to install the improved reader. Change
the Noctalia palette, return to the same shell and reach a new prompt; inspect syntax
and table colors. Test light/dark separately and confirm Atuin, completion, navigation
bindings and other prompt integrations still work. Existing old readers at the default
state path can consume the new data, but lack the new partial-read protection.

## Native wallpaper migration (accepted)

`noctalia/wallpaper.nix` enables the native wallpaper renderer, placed by Niri within
its backdrop only. Noctalia's extra backdrop renderer is disabled. Crop and one-second
fade preserve the basic appearance; wallpaper must not be inside workspace previews. The two mountain images are path-only favorites, without theme/palette
presets. Palette source remains independent. Native automation is disabled.

V5 supports mode-aware browse directories, but doesn't directly apply this fixed
image pair on mode change without rotation or an extra command. Initially the temporary
bridge chose the resolved light/dark image through `wallpaper-set` instead of awww.
The accepted follow-up below moves that selection to native hooks. That IPC persists
the default/current-output paths; Noctalia owns rendering, transitions and output
handling. Niri determines the backdrop-only placement.

Niri startup no longer spawns awww; its package and active backdrop rule are removed.
The new rule places `^noctalia-wallpaper$` within Niri's backdrop. The custom udev
monitor-hotplug service/script are removed. No replacement daemon or restart helper
is added. The Darkman rollback code and the awww flake input were also removed.

### Existing-session handover

The initial two-renderer trial duplicated wallpaper inside workspace previews.
The corrected configuration uses a single `noctalia-wallpaper` surface within Niri's
backdrop, with no `noctalia-backdrop` surface. The user rebuilt and confirmed transparent
workspace previews and working fades between light/dark wallpapers.

A rebuild did not kill the loose awww daemon launched earlier by Niri. Native
wallpaper/backdrop surfaces, the selected mountain image and successful texture
changes were verified first. The pinned official `awww kill` IPC then retired that
old backend; process/layer inspection confirmed its exit. Niri was not restarted.
No automatic migration/process-kill hook is installed. After the corrected rebuild,
expect only `noctalia-wallpaper` behind overview (plus the normal bar/panels), no
awww or extra backdrop, and no wallpaper inside workspace previews.

Test desktop/overview appearance, manual dark/light changes, monitor reconnects and
Noctalia restart behavior. Native surfaces depend on the shell, so a restart may
briefly remove the background. Manual picker selections can be used, but a later
mode/forced-startup refresh restores the declarative pair under the retained policy.
GUI wallpaper default overrides are reconciled by the native mode-pair IPC, not by
rewriting the whole settings.toml. Tests mock IPC, never alter live wallpaper state.

At the initial migration, two bridge tests covered image choices/no reverse palette
writes and native-error retries. The independent-policy tests below replace them;
the bridge now tests that it never selects wallpaper. Invariants enforce no active awww package/startup or custom
hotplug service, a disabled extra backdrop and path-only favorites. An additional
Niri regression checks the ordinary wallpaper's backdrop placement. Full config/Niri validation,
lint and Framework build pass. Live inspection verified the single native wallpaper
layer, disabled extra backdrop, absent awww process/hotplug service, correct dark image,
valid full Niri config and active shell/overview services. Appearance/fades are accepted;
monitor reconnect and shell-restart behavior remain untested.

### Independent native wallpaper-pair policy (startup/mode accepted)

Source review is against pinned V5.3.0 a33122c, not current upstream docs. Its
wallpaper directories resolve light/dark folders but only pick images on manual
commands or startup/interval rotation. They do not immediately apply this fixed
pair when app mode changes. Enabling rotation or changing the user's browse folder
is unnecessary; keep the existing default, path-only favorites and disabled automation.

wallpaper.nix now registers one external wallpaper-mode.sh helper in both native
started (IPC ready) and theme_mode_changed hooks. Its separate per-session flock
serializes overlapping children; each reads theme-mode-get inside the lock instead
of trusting NOCTALIA_THEME_MODE from an older queued event. It then sets only the
corresponding existing mountain image using native wallpaper-set (all connected
outputs/default). Calls have 10s/30s limits and lock acquisition 45s. Invalid mode,
command failure or non-ok IPC reply fails without guessing a mode/image or reverse
mode/palette writes. Native async hooks discard stdio, so bounded 2s logger calls
record selection/errors under tag noctalia-wallpaper-mode; logging failure does
not undo accepted IPC. No runtime directory creation, persistent poller, service, HM wait, Nix
build/activation, settings rewrite or process restart is added. A subsequent native
startup/mode event retries the policy; there is no new automatic retry daemon.

The retained theme bridge no longer imports wallpaper assets, exports wallpaper
environment or calls wallpaper-set. Its refresh flag now requests only native
templates-apply, checking the reply and retaining failed work for retry. Existing
pre-session lock/defer/readiness protections remain. Native hooks retain the bridge
request alongside image selection, so remaining prebuilt consumers still update.
No swaylock/PAM, idle, inhibitor, hardware, styling/layout or shared/Darwin change.

14 new private-runtime/fake-IPC tests exercise the actual rendered helper, both
images, auto/current-mode resolution rather than stale event payload, overlapping
processes with actual flock, repeat startup, bounded calls, errors, path quoting,
registration and bridge independence; logger calls also target private fixtures,
never the real journal. All 172 Noctalia + 19 suspend tests, 17 Linux
checks, full Framework build, formatting/lint and Nix diagnostics pass. Those checks
alone are not real mode/startup/reconnect acceptance. Relevant GUI hook/favorite overrides
were inspected read-only; none needed migration. settings.toml was not edited.

User validation, while unlocked: rebuild switch, select Light then Dark in Noctalia
and confirm the matching image/fade and unchanged transparent overview previews;
restore Auto. Then inspect worker/path/native state without restarting anything.
The user rebuilt while unlocked and accepted the requested mode/appearance check.
Noctalia started at 14:06:03; the native hook selected light at 14:06:04, dark at
14:06:13 and light at 14:06:17. The rebuild therefore exercised the startup hook as
well as later mode changes. Auto was restored (no theme-mode GUI override), native
mode-get returned light and wallpaper-get returned the configured light mountain.
The internal display had one noctalia-wallpaper layer and no extra backdrop.
Noctalia/overview remained active with the same start timestamps through the later
mode changes; HM succeeded, bridge completed normally with zero restarts and its
path watcher waiting. No failed user units remained. Agent verification was read-only;
all activation/mode changes were user-operated.

Accept the observed shell-startup/mode-pair behavior, not a fresh OS boot of this
policy or coverage of disconnected/external outputs. Monitor reconnect and broad
restart appearance remain separate, previously deferred checks. Keep the
bridge/specialisations and fallback/auth until their own retirement gates pass.

## Remaining consumers and native Starship palette (accepted)

The audit compares actual enabled managed files across specialisations, not just
Stylix target flags: many targets emit assets for apps not actively configured.
Mode-dependent outputs still include swaylock, btop/gdu, GTK source styles, Vencord,
Blender/Forge/Xresources and some environment/font paths. Package-generated Emacs
configuration also needs review before removing the compatibility generations.

SwayOSD's service has no mode-varying stylesheet here, but volume-ctl delegates the
actual volume operation to its client. Replacing it with Noctalia OSD is a separate
functional migration. This step leaves all volume/brightness/DDC controls, Framework
audio initialization and lock/authentication code unchanged.

`noctalia/starship.nix` consumes the shipped Starship palette unchanged. Since Starship
has no config include, a build-time concatenation composes the actual declarative
Home Manager base (including any presets) and that palette input. Noctalia renders
the complete runtime file to `$XDG_STATE_HOME/noctalia/starship.toml`. The managed
base remains immutable and its fixed Base16 palette is disabled. No template hook
rewrites it, no process-environment scan or runtime merge service is introduced.

STARSHIP_CONFIG points at runtime output in home session vars and Nu environment.
Shared/Darwin settings and the existing prompt format/module/integration remain
unchanged. The standard output preparer seeds a valid comment until rendering and
handles protected data with backup. Native Starship reads config each invocation;
open a fresh Nu session after rebuilding to install the new pointer. Edit prompt
settings in Nix, not the generated runtime file. Don't enable the duplicate built-in
catalog entry with its config-mutating hook.

Six tests render two palettes/both modes, invoke real Starship prompt/config commands,
verify ANSI RGB, verbatim input/base composition, config pointers and protected/
bootstrap behavior. They never change an active prompt. Full build/native config/
cache/invariants/lint pass. After rebuilding, open a fresh Nu shell, select another
Noctalia palette and reach a new prompt; test light/dark separately. The regular
prompt layout should stay the same. The user rebuilt and confirmed it works.
Live inspection verified the immutable base, writable runtime config, selected
native palette without Base16, installed Nu pointer and real ANSI RGB prompt output.
Shell/overview services remain active. Detailed integrations were not independently
instrumented beyond automated tests.

## Native output-volume and brightness OSD (accepted)

`noctalia/osd.nix` enables native output-volume and brightness OSD, with overdrive
and input-volume OSD disabled. SwayOSD is disabled and removed from active controls.
The Niri volume keys call Noctalia's native 5% up/down and mute commands; the same
audio service supplies bar and OSD state. The cap is 100%. Horizontal/vertical OSD positions are bottom_center, as requested,
so popups don't cover the topbar. Noctalia availability is
now required for these keyboard volume commands; no second backend is added.

The old volume cache helper/startup entry is removed. Existing cache data is not
deleted, inactive rollback files are untouched, and media keys remain playerctl.
Framework pw-loopback startup initialization is preserved exactly.

Brightness still uses brightnessctl in synchronous 5% steps and the existing
asynchronous DDC target/catch-up worker. Only display switches to native
brightness-osd <actual%>; it never asks Noctalia to change brightness again.
An OSD failure still allows external synchronization; failed internal adjustment
exits before stale values propagate. Target/lock files now live in per-user runtime
state rather than shared /tmp paths. DDC locking/catch-up behavior is otherwise
unchanged. No agent hardware changes are used for testing.

The compatibility bridge no longer restarts SwayOSD or any other UI client. It
still applies remaining prebuilt theme consumers and native templates. The accepted
wallpaper-policy follow-up removes its image-selection role, not its other consumers.
Do not remove it solely because its explicit client restart list is now empty.

### Framework function-row preference

Use hardware Fn Lock (Fn+Esc) for normal F1–F12 with media actions behind Fn.
On this Framework 13 Ryzen AI 300, Fn+F3 then sends volume-up while F3 reaches apps.
Niri continues binding XF86 media events, not bare function keys; the external
NuPhy udev/WebHID rules remain separate. No firmware command or simulated
key press is run by the agent. [Framework guidance](https://community.frame.work/t/setting-f-keys-as-default-instead-of-fn-keys/69667/2)
reports persistence across reboots; firmware resets/updates may require retoggling.
The user confirmed the desired function-row behavior, but reboot persistence was
not independently tested by the agent.

Eight tests use fake brightnessctl/DDC/Noctalia programs, validate native volume key
wiring without executing it, check limits/audio initialization, catch-up, lock/error
paths and invalid actions. Existing Niri/config validation still covers all binds.
Full build/cache/invariants/statix/shellcheck pass. The user rebuilt and confirmed
the native controls, bottom-center position and Fn preference work. Live inspection
verified the retired SwayOSD service, native 5%/mute binds, output/brightness flags,
100% limit, display-only brightness call and preserved pw-loopback initialization.
Niri validation and shell/overview services are healthy. No hardware settings were
changed by the agent; external-monitor behavior was not separately instrumented.

After rebuilding, test volume down/up/mute, then internal brightness down/up and
external sync if connected. Expect a single native OSD, matching bar/device values,
with current Noctalia palette colors. Native sound preferences remain in effect;
report unwanted feedback separately. Authentication/idle/power behavior is unchanged.

## btop built-in template (commit approved; live test deferred)

`noctalia/btop.nix` enables the unmodified shipped btop template and disables its
fixed Stylix theme. The main config declaratively selects `color_theme = "noctalia"`,
retaining `update_ms = 1000` and `vim_keys = False`. Shared/Darwin behavior is unchanged.
Only `~/.config/btop/themes/noctalia.theme` is writable runtime output, prepared with
a valid comment/protected-output backup handling before linkGeneration.

The pinned apply hook recognizes that fixed selector and skips writes through the
Home Manager symlink. It then uses SIGUSR2 for native btop reload. Six tests validate
two palettes/both modes and run the hook with fake process tools. A real btop 1.4.7
sandbox child starts in a PTY, reads the first RGB theme, receives SIGUSR2 only on
that exact child PID, and displays a second palette without config changes. No live
user process is signalled by tests; no custom reload watcher/controller is added.

Full build/native config/cache/invariants/lint pass. After rebuilding, open btop,
select a different Noctalia palette and test light/dark separately. Expect colors to
change in the running instance while refresh interval/keybindings stay unchanged.
Confirm the main config remains a managed symlink and the old Stylix theme is gone.
The user explicitly requested committing without live testing. Deployment and live
palette/reload/GUI behavior remain unverified despite the passing automated tests.
Lock screen/authentication and other remaining consumers are outside this checkpoint.

## Plain Emacs native theme (commit approved; live test deferred)

The routing audit distinguished Home Manager's plain `emacs` final package from
personal Doom/Spacemacs wrappers, which launch raw emacs-pgtk with separate init
directories and personal doom-one/spacemacs-dark themes. No default daemon is
configured. `noctalia/emacs.nix` changes only the managed plain route; it neither
edits those profile files nor signals their clients.

The unmodified shipped Lisp template renders to
`$XDG_STATE_HOME/noctalia/emacs/noctalia-theme.el`. The managed init preserves its
previous font/opacity expressions, adds the runtime directory to theme lookup and
loads Noctalia at startup if readable. A valid empty theme covers initial startup
until rendering, and the shared preparer safely handles protected output.
The fixed Base16 dependency disappears; the plain final package is identical across
specialisations. Shared/Darwin settings remain unchanged.

The built-in output-discovery/client hooks are not used: discovery picks Doom's
personal root first, and emacsclient assumes a default server. Startup loading is
explicitly not live switching; restart the plain app or reload the theme manually
for new colors. Upstream also sets Org hide-leading-stars/startup-indent preferences
and styles generic fixed/variable-pitch faces. Those theme behaviors are retained,
not hidden by a fork.

Six tests load the actual rendered theme in real batch Emacs for two palettes/both
modes, validate face colors/opacity/bootstrap and unchanged personal routes/files.
Batch TTY font resolution is not GUI font validation; source checks preserve the
original font-spec. Native config/cache/invariants/lint/full build pass. After a
user rebuild, test **plain emacs**, not doom-emacs/spacemacs; choose a Noctalia palette
and restart/reload the plain theme. The user explicitly requested committing without
live testing; deployment, GUI appearance and GUI font resolution remain unverified.
Passing automated batch tests are not live acceptance.

Swaylock remains unchanged, including manual/idle/pre-sleep routes and custom
fingerprint/lid-aware PAM. xterm is installed, so Xresources needs a real plan;
other generated dormant-app assets need confirmation before removal. Do not retire
the compatibility bridge merely because some generated files look unused.

## Dormant target/KDE overlay cleanup (commit approved; activation unverified)

The post-Emacs audit found no configured Blender/Forge/gdu/gedit/Vencord or KDE/
Plasma app installation in the declared home/system inventory or local Flatpak app
list. These targets emitted files despite the absent app setup. `stylix.nix` now
disables only those six generators; this is not a claim about never-used transient apps.
No application is uninstalled. Native fonts/cursor/Papirus/Qt configs are retained.

The KDE target was the sole mode-varying XDG_CONFIG_DIRS injection. Retiring it
also stabilizes environment/fontconfig/autostart generated outputs. Eight files
still differ between prebuilt modes: Xresources, Stylix palette HTML/JSON, swaylock
and four GTKSourceView style versions. xterm is installed, so Xresources stays;
shared viewers can use GTKSourceView, so those files stay too. Authentication and
personal Emacs profiles remain untouched.

Invariants reject dormant assets/the old KDE environment overlay while retaining
protected consumers. Full Framework build, all 119 Noctalia/11 suspend tests, cache
checks and lint pass. After the user's rebuild, inspect owned orphan links and check
ordinary fonts/icons/cursor/Qt appearance. Home Manager should not delete non-owned
copies; do not force-remove user files. Old processes can retain inherited KDE config
values until a future login—no live session environment rewrite is performed here.
The user explicitly approved committing and continuing without activation verification.
Live cleanup/desktop regression acceptance remains unverified; bridge removal is a
subsequent checkpoint.

## Xresources native colors (commit approved; live test deferred)

xterm is installed and reads the Xwayland resource database. Neither pinned template
catalog provides Xresources, so `noctalia/xresources.nix` uses a small local color-data
template in the native renderer. It emits `$XDG_STATE_HOME/noctalia/Xresources`.
The Nix-managed ~/.Xresources includes that file through native preprocessing,
keeping font/cursor properties declarative. The previous Xresources/Sxiv static
color targets are disabled; Sxiv font/colors remain available if that app is used.

A guarded native xrdb -merge hook loads the complete managed resource file only
when DISPLAY exists. It doesn't modify the main file or choose theme mode/palette.
The preparer ensures a valid Xresources comment before import links are installed
and safely handles protected legacy output. No new daemon/controller/app wrapper
is introduced. Existing xterm windows may keep startup colors; new instances read
the current database. The agent has not merged into the user display or launched apps.

Six tests run the actual xrdb preprocessor and merge in isolated headless Xvfb
servers with TCP disabled. They verify two palettes/both modes, unchanged fonts/
cursor/unrelated resources, idempotence, protected main files and bootstrap/no-display
behavior. They are not GUI/font-resolution or existing-xterm hot-reload tests.
Native config/cache/invariants/lint/full Framework build pass. The user explicitly
requested committing without live testing. Deployment and new-xterm GUI appearance
remain unverified; isolated-server tests are not live acceptance.

After rebuilding, change the Noctalia palette, open a new xterm and check colors/
fonts/cursor. Test light/dark separately; don't expect an already-open window to
recolor. `xrdb -query` is a read-only way to inspect the published values. Swaylock,
PAM and personal Emacs profiles remain untouched; bridge removal is still separate.

## GTKSourceView native colors (commit approved; live test deferred)

A saved Gedit scheme setting still names 'stylix'. Although Gedit isn't installed,
removing that available scheme could break a future/current shared consumer. No
Noctalia entry exists in the pinned catalogs. `noctalia/gtksourceview.nix` reuses the
pinned upstream XML syntax/style definitions and translates only color placeholders
to Noctalia tokens at build time. The visible label is Noctalia; legacy ID and lookup
filenames stay stylix, preserving saved selections without changing app preferences.

Noctalia writes one state XML; versioned GTKSourceView 2.0/3.0/4/5 style directories
link to it through out-of-store symlinks. The old fixed target is disabled. The common
preparer seeds a valid empty scheme and safely handles protected output. No app code,
preference writer, hook, GUI launch or new service is added. Existing style-manager
instances can cache data; reopening apps or rescan may be required. Apps selecting
other schemes keep them—this integration does not force every preview/editor to use it.

Six tests preserve the upstream style definitions, render two palettes/both modes,
check lookup/legacy/preference behavior and load the current colors through real
GTKSourceView 4 and 5 managers in separate headless processes. Version 2/3 parser and
GUI appearance are not tested. Native config/cache/invariants/lint/full build pass.
The user explicitly requested committing without live testing; deployment and GUI
appearance remain unverified. Native style-manager tests are not GUI acceptance. After rebuilding, an app selecting the
legacy stylix ID should show Noctalia colors on its next scheme load. No extra app
was installed just to test this.

Only swaylock and the diagnostic palette JSON/HTML remain mode-dependent managed
files. Lock/PAM are unchanged, and the compatibility bridge remains until its final
real consumer has a separately reviewed migration.

## Native lock screen: stage-one PAM preflight (accepted)

The user chose native Noctalia locking. This is staged: the native screen stays
disabled and all existing swaylock/idle/manual/sleep routes remain unchanged until
authentication is checked manually. No lock or password test is run by the agent.

V5.3.0 hardcodes password PAM service login; this host's login has fingerprint/lid
rules, while native Noctalia handles its reader over D-Bus. A small exact-context
package patch selects a dedicated noctalia password stack instead of changing TTY/
login services. Its old comment claimed PAM filtering, but the reviewed implementation
uses pam_start directly. Patch fuzz is disabled so upstream drift fails the build.

The new desktop PAM service requires pam_unix authentication/account checks without
nullok, permit, fingerprint or login includes. Generated login/swaylock/sudo/greetd/
polkit-1 files were compared unchanged against the deployed files. The patched binary
is used by existing regression tests; compilation and the new auth-stage invariant
pass, but neither is proof of valid/invalid password handling or native fingerprint.

The user rebuilt and confirmed private pamtester checks: correct password succeeds,
incorrect password fails. That accepts only password PAM; a separate cutover still
needs native screen/route validation. Fingerprint/account
policy, suspend delay, DPMS and compositor recovery also need review. Keep swaylock
as the working current path for now. See the [staged migration guide](noctalia-lockscreen-migration.md).

## Native lock screen: manual trial (password/fingerprint accepted)

Stage-one password preflight is accepted/committed. `noctalia/lockscreen.nix` enables
the native manual screen and Mod+Shift+X route with grace/empty-password/desktop
capture/transitions disabled and all outputs covered. Native fingerprint is enabled,
but not yet manually tested. The duplicate swayidle logind Lock listener is removed.

Automatic idle lock (300s) and before-sleep still use swaylock; monitor power (305s)
and safe-suspend (310s) stay as before. Native lock_before_suspend is false and
native idle behaviors are disabled for this trial. No automatic cutover or sleep/
DPMS/fingerprint actions are performed by the agent. Those routes are a later stage.

Native fingerprints claim fprintd for the current D-Bus user, release on stop and
pause around sleep. Password submission stops the reader before dedicated PAM.
Native fingerprint success directly unlocks without PAM account checks, so restricted/
expired-account semantics aren't identical to the old PAM path. Existing root lid/
fprintd configuration is unchanged; do not claim account-policy parity.

Four static policy tests and full build/config/auth/cache/invariants/lint pass.
They do not prove GUI/session-lock/fingerprint behavior. Save work and establish a
TTY/password recovery route before applying; apply only while unlocked. Manually
test password (avoid the sensor first), wrong-password rejection, fingerprint and
all outputs. Do not stop/restart Noctalia while locked expecting to unlock: an
abandoned lock can stay secure. See the [migration/recovery guide](noctalia-lockscreen-migration.md).
The user activated this stage and confirmed password and fingerprint unlock work.
Live inspection verified native secure defaults/manual binding, retained automatic
swaylock paths and active native services. Wrong-password UI, multi-output coverage
and sleep recovery remain separate checks. Automatic routes still use swaylock.

## Native automatic lock/sleep route cutover (activated; basic integration verified)

Native password/fingerprint unlock, wrong-password UI rejection, keyboard suspend
and lid sleep/wake have passed their reported checks. The automatic swayidle trial
found two integration issues: timer-only logind initialization and then a Bash-only
service PATH, which caused `safe-suspend: command not found` at 310s. That full idle
trial did not suspend. The user approved replacing swayidle with native idle.

Configured `noctalia/idle.nix` enables native lock at 300s, screen_off at 305s and
lock_and_suspend at 310s. Native screen_off restores monitors on activity. Explicit
order, zero pre-action fade and locked_timeout=0 preserve elapsed timing rather than
adding the default fade or restarting a waiting timeout on lock. No idle shell
commands or custom resume controller are introduced. Swayidle is disabled, no user
unit is generated and its temporary package patch is removed.

Native lock-and-suspend waits for the native lock, then uses the configured absolute
safe-suspend --require-lock power backend. The shared explicit-PATH package also
supplies the keyboard shortcut and profile command. Existing blocker checks and
positive logind LockedHint guard are preserved; that hint isn't independent
compositor attestation. Native lock_before_suspend and the strict policy patch keep
external sleep protection authoritative. The five-second logind delay bound remains
unchanged; upstream bounded delay is not an infallibility guarantee.

Reviewed ScreenSaverService subscribes to logind BlockInhibited and supplies idle
blocks to IdleManager, supporting the existing audio idle:sleep watcher. Native idle
also respects screensaver/Wayland inhibition and Caffeine. Keep the audio watcher,
root fingerprint/lid policy, tuned, Lid Guard and 30s post-resume lid holdoff unchanged.
Live inhibitor tests remain necessary. The GUI audit found no idle/session overrides;
no user settings were discarded.

Swaylock/PAM/style remain recovery-only until automatic acceptance. No bridge or
specialisation cleanup is bundled. Eight policy/native-parser probes and 19 mocked
suspend-helper tests pass (139 total Noctalia tests), along with full Framework build,
config/auth/cache/theme checks and lint. No real session/hardware action by agent.

Activate only while unlocked with saved work and recovery ready. First inspect
Noctalia/overview health, native behavior registration and sleep-delay inhibition,
and confirm swayidle stopped. Then the user can leave input untouched for six minutes
and wake with a regular key; kernel logs must establish sustained sleep, not merely
a black monitor. User activated the cutover: swayidle is absent, native behaviors
are registered, idle monitoring/sleep-delay are active and the absolute backend is
deployed without GUI overrides. The user completed a native automatic trial and
confirmed their key press caused resume; logs verify lock/screen-off/suspend at
five-second intervals, actual kernel sleep and healthy resume. Basic Caffeine/audio
acquisition, native recognition and release were verified independently. On the
updated stack (2026-10-23) the user separately completed full idle intervals with
Caffeine alone and Audio Playback alone: all three native callbacks were explicitly
suppressed and the screen stayed on/unlocked. User Caffeine release at 14:37:57 and
audio release after pause at 14:56:45 were verified. With audio still holding
sleep:idle/block, a user Mod+Shift+S attempt produced Suspend Blocked, with no
observed lock/sleep. This verifies the guarded manual helper veto, not raw logind
or every panel action; Lock and Suspend may lock before its backend veto.

The owner deferred reader-unavailable fallback, external-output/reconnect coverage
and the unresolved power-button interaction to the [backlog](noctalia-backlog.md).
Revisit when encountered/requested, not as immediate mandatory tests. They are not
accepted, and fingerprint causality is not established. Ordinary cleanup can continue
without changing recovery; fallback/auth retirement still requires separate review.
See the [stage history and recovery guide](noctalia-lockscreen-migration.md).

## Pre-session Home Manager activation and stale Nu bindings

After booting the rebased generation on 2026-10-23, the kernel was 6.18.52-cachyos,
but home-manager-frank.service failed in noctaliaThemeLock before linking files.
The old hook attempted to create /run/user/1000 before login; permissions correctly
prevented this. The bridge then deferred against the failed system unit. Old home
files remained while /etc/profiles/per-user/frank already supplied newer packages.
The reported Nu warning came from an Atuin 18.19.0 generated script, not the current
18.23.0 wrapper. The current generated integration passes the real Nu uniqueness
probe with Ctrl-R/Up and modes retained. No warning-suppression/keybinding rewrite
is needed for this symptom; the shared Atuin/Darwin configuration is not changed.

The fix uses a private persistent shared lock and leaves runtime-dir
creation to systemd/logind. When an owned runtime already exists, activation exports
it for later user-service integration and retains legacy lock serialization. Darkman
is queried/stopped only with a bus and before locking. The overview ensure hook
skips pre-session bus access; its normal graphical-session startup still owns boot.

Pre-login theme requests are deferred until native shell startup. A forced request
from ordinary HM activation invalidates only theme-bridge.json, the applied-generation
cache: otherwise an identical cached mode could hide the fact that base activation
just replaced specialised files. settings.toml/preferences remain untouched. Both
request and worker use the configured state home and the explicit shared lock path.

All 158 Noctalia tests and the full Framework build pass; real hook fragments run
only against private fixtures/fake systemctl, and all generation activations are
mocked. Request deferral, cache invalidation/startup reapply, cross-caller locks,
dry-run/child skips, overview startup and Nu warning detection are covered. No
agent activation or service/power/authentication action was performed.

The first live recovery passed the lock/file-link stages, but blocked in reloadSystemd.
sd-switch started the then-oneshot theme worker and waited for it; that worker was
waiting for the system HM unit that was itself awaiting sd-switch. Killing the nh
frontend did not stop the system activation. It eventually timed out and failed.
The native Noctalia shell remained running. This readiness interaction was not
covered by the earlier hook-only fixtures; do not call that attempt successful.

The follow-up changes the finite worker to Type=exec, marking startup after exec
rather than after its work completes. It still waits for HM before acquiring locks
or activating a specialisation. Unit definitions stay identical across variants,
and the invariant/probe rejects oneshot readiness. Normal HM requests asynchronously
ensure the path watcher is started, including after manual recovery. No persistent
poller or new mode controller is introduced. The subsequent retry and boot below
provide live evidence; contract/parser/fixture checks alone are not that evidence.

Before retrying while unlocked, the user can stop only the retrying adapter with
`systemctl --user stop noctalia-theme.path noctalia-theme.service` (not noctalia.service),
then run rebuild switch with the completed fix and open a fresh terminal. Inspect
system HM success, current config link, Type=exec bridge readiness and restored path
watcher. No reboot is needed for that immediate check. A separate user reboot is
required to establish the pre-login path; fixture/build success alone is not a
completed boot test. Both steps were subsequently completed as recorded below.

The subsequent user retry completed: system HM activation ran 11:11:02–11:11:06
with Result=success; the Type=exec worker then applied/refreshed the light mode and
finished at 11:11:09, leaving its path watcher waiting. The live Nu config now sources
the current Atuin integration with unique names. Two pre-rebuild Nu sessions were
still resident; existing processes retain their loaded definitions/config even when
home files change. A later paste-related report still named the old 18.19.0 store
file. The user then confirmed a fresh terminal runs `echo test` normally and
copy/paste works without that warning. Accept the live activation/readiness and
reported fresh-terminal behavior. Clipboard contents were not inspected and no
paste/keybinding workaround was applied.

The user then rebooted and confirmed it still works. On the 11:32 boot,
home-manager-frank.service completed successfully at 11:32:10 before the user daemon
or runtime directory existed. Standard reload was skipped and the theme request
explicitly deferred. Session startup ran the Type=exec worker at 11:32:14, applied
the prebuilt light specialisation and refreshed at 11:32:19. It exited normally with
zero restarts, its path watcher waiting, and native shell/overview active. No failed
system/user units remained at inspection. A transient degraded-session notice had
no listed failed services and did not prevent completion.

Accept the observed warm activation, fresh-terminal/paste behavior and reboot/
pre-session activation path. This does not close unrelated lock/output/reader or
power-button follow-ups. Do not clear the whole settings file, restart a locked
shell or activate a generation as an agent.

## Consolidation plan

The next steps are documented in [Noctalia consolidation research and plan](./noctalia-consolidation-plan.md):
peripheral batteries, storage, separate Caffeine/lid controls, native battery alerts,
and moving runtime theme control from Darkman to Noctalia. OpenRouter and firewall
summary widgets are no longer required. Headphone battery visibility has been accepted;
the storage trial has passed its basic live test. Native Caffeine passed its inhibitor
and idle tests, and the Lid Guard trial is accepted. Native battery warnings are
accepted after deployment checks. The palette-warning fix is accepted; the runtime
controller handover and Ghostty's native palette propagation have passed their live
tests. The GTK checkpoint is approved with Files/GTK3 checks deferred; Qt is the next
isolated migration with runtime palette propagation verified; Vicinae is now
accepted by the user, as are Zed, Zen Browser, VS Code, lazygit and fzf's reviewed
Nushell-compatible wrapper. Cache trust revocation is verified and Niri is accepted.
Nushell is accepted; the remaining-consumer audit, deferred GTK checks, bridge
cleanup and artifact-integrity review remain separate.

## Build and validate

```sh
nix build --accept-flake-config .#nixosConfigurations.framework.config.home-manager.users.frank.programs.noctalia.package
nix build --accept-flake-config '.#nixosConfigurations.framework.config.home-manager.users.frank.xdg.configFile."noctalia/config.toml".source'
nix build --accept-flake-config .#checks.x86_64-linux.noctalia-overview
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

Checkpoint `77d6c20` (originally `3f51f68`, before the origin rebase) is the
accepted Noctalia palette configuration before the
runtime-controller handover. To roll back that handover, restore the controller's
system/HM imports, remove its path/worker/hooks, and reconcile only relevant saved
`theme.mode` overrides. Keep newer plugin/UI choices rather than overwriting all state.

The older custom shell, notification daemon and theme controller were removed from
this tree as part of the Noctalia consolidation. Rolling them back now means checking
out an earlier commit and deliberately restoring the relevant imports; never run both
shells/notification daemons together.

## References

- https://github.com/noctalia-dev/noctalia/tree/v5.3.0
- https://docs.noctalia.dev/noctalia/getting-started/nixos/
- https://docs.noctalia.dev/noctalia/compositor-settings/niri/
- https://docs.noctalia.dev/noctalia/plugins/
