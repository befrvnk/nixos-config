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

## Overview watcher lifecycle

`noctalia-overview.service` is wanted by the graphical session, ordered after
Noctalia, and stopped with it. The native `started` hook restarts the watcher once
IPC is ready. Home Manager also idempotently starts the watcher after reloadSystemd.
This second path is necessary: unit reconciliation can stop a PartOf dependent
while a concurrent job cancels the shell's own restart. The shell stays alive,
its started hook never runs, and an otherwise healthy overview-only bar stays hidden.

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
suppresses its own activation hooks. It then refreshes SwayOSD and awww.
Nushell's runtime data is now written only by Noctalia's native template renderer. Duplicate events skip activation; newer events and
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

Build validation includes 16 mocked bridge tests, 4 overview tests, 10 Ghostty
integration/migration tests, 6 GTK tests, 4 Qt tests (with real offscreen Qt5/Qt6 probes),
6 Vicinae tests (with its actual pinned theme parser), 6 Zed tests (including the actual
Home Manager settings merger), 7 Zen tests (including actual packaged policy checks),
6 VS Code tests (including isolated CLI extension discovery), 6 lazygit tests
(including real isolated PTY/color checks), 7 fzf tests (real Nu/selectors/PTYs),
6 Niri template tests (full KDL validation with runtime colors), 6 Nushell tests
(real Nu rendering/reader/hook checks), 11 safe-suspend tests and
`checks.x86_64-linux.noctalia-theme-invariants`. The latter verifies identical
shell/bridge service definitions across theme generations to prevent restart loops.
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
The upstream hook calls `vicinae theme set noctalia`; v0.23.0 rescans and reloads the
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
