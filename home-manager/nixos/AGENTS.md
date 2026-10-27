# NixOS Home-Manager Configuration

NixOS-specific user configuration including Wayland, systemd services, and Stylix theming.

## What Goes Here

- Window manager config (niri/)
- Desktop shell (noctalia/, native C++ V5)
- Noctalia runtime theme control (noctalia/theme.nix) + temporary Stylix app specialisations
- User systemd services
- Wayland-specific apps
- Anything using `config.lib.stylix.colors`

## Theming System

### Noctalia + temporary Stylix Architecture
1. **Noctalia** (`noctalia/theme.nix`): Runtime manual/automatic mode and portal preference owner.
2. **Home-Manager Stylix** (`stylix.nix`): Prebuilt app-theme specialisations during migration.
3. **Compatibility adapter** (`noctalia/theme_bridge.py`): One-way, serialized application of those generations.
4. **System Stylix** (`modules/theming/stylix.nix`): Static system defaults; not the runtime controller.

### Writable output preparation
- Apps declare their writable runtime outputs through `noctalia.prepareOutputs`
  (`noctalia/prepare.nix`). One `prepareNoctaliaThemeOutputs` activation entry runs
  `prepare_theme_output.py --manifest` once, between `linkGeneration` and
  `writeBoundary`.
- Never add a per-app `home.activation.prepare*` entry: each spawn cost ~150 ms of
  the boot-critical `home-manager-<user>.service` (17 entries ≈ 3.3 s of the 4.3 s
  unit, which gates `systemd-user-sessions` and greetd).
  `checks.x86_64-linux.noctalia-theme-prepare` enforces the single batched entry.
- `placeholder = null` keeps the preparer's own default seed (Ghostty's). The
  manifest is JSON, so paths and placeholders are never shell-interpolated.
- `test_prepare_manifest.py` is picked up by the `test_*.py` discovery in
  `checks/noctalia.nix`; it covers placeholder defaults, skipping prepared outputs
  and the still-supported positional form.

### Stylix Color Injection
```nix
{ config, ... }:
let
  colors = config.lib.stylix.colors;
in {
  xdg.configFile."app/style.css".text = ''
    @define-color base00 #${colors.base00};
    @define-color base01 #${colors.base01};
  '';
}
```
Use this only for remaining static targets during migration. Niri now uses Noctalia's
built-in runtime color include; don't reintroduce fixed border colors into layout.nix.
The compatibility adapter still selects prebuilt generations for remaining consumers.

### Specialization Pattern
Theme switching without full rebuilds:
```nix
{
  stylix = { /* base config */ };

  specialisation = {
    dark.configuration = {
      stylix.polarity = lib.mkForce "dark";
      stylix.base16Scheme = lib.mkForce "catppuccin-mocha";
    };
    light.configuration = {
      stylix.polarity = lib.mkForce "light";
      stylix.base16Scheme = lib.mkForce "catppuccin-latte";
    };
  };
}
```

### Theme Switching (Noctalia)
- `theme_mode_changed` and startup hooks submit atomic requests; `noctalia-theme.path`
  drives a finite `Type=exec` worker. `Type=oneshot` deadlocks HM unit switching:
  sd-switch waits for worker completion while the worker waits for HM. Exec startup
  readiness must precede that wait. Normal activation asynchronously ensures the
  path watcher is started after reload; do not restart a worker mid-activation.
- Worker reads `theme-mode-get`; it never writes a mode or portal preference back.
  It requests native `templates-apply` after HM activation so Noctalia owns preference sync.
- Stylix's GNOME target is disabled: it writes `default` for light mode and would fight
  Noctalia. Static app fonts are preserved explicitly; do not reintroduce an HM-managed
  `org/gnome/desktop/interface.color-scheme` key.
- Normal HM activation and the worker share the canonical persistent
  `${config.xdg.stateHome}/noctalia/theme-activation.lock`; the worker gets its path
  explicitly. Both also hold the old runtime lock, when available, to serialize
  with older generations during upgrade/rollback. Always take state before runtime.
- HM's system unit can run before login: never create `/run/user/$UID`. Defer theme
  requests when runtime is missing, and guard overview/user-bus calls until a bus
  exists. Normal activation invalidates only the applied-generation cache; startup
  must reapply the mode even when the previous cache had the same generation/mode.
  Never erase GUI settings to recover activation. Warm activation, fresh Nu/paste
  and pre-session activation after a user reboot passed on 2026-10-23; keep the
  readiness and pre-session regression probes when changing this temporary bridge.
- `NOCTALIA_THEME_BRIDGE_ACTIVE` suppresses recursive hooks/locking in the worker's child activation.
- Noctalia config and shell/bridge units must be identical across dark/light generations
  (`checks.x86_64-linux.noctalia-theme-invariants` enforces this).
- Neither system nor HM Darkman module is imported. Old files remain rollback-only.
- Ghostty, GTK3/GTK4 and Qt use Noctalia's built-in templates; Vicinae consumes a
  reviewed pinned community template, as does Zed. Other apps migrate individually.
- Keep Ghostty's main config declarative with literal `theme = noctalia`, so the shipped
  apply hook skips rewriting its read-only symlink. Never manage `themes/noctalia` as
  `home.file`; it is a separate writable runtime output.
- `noctalia/ghostty.nix` prepares legacy read-only theme output before linkGeneration,
  backing up once without modifying symlink/hardlink targets. The pinned apply hook and
  template rendering are tested with a fake reload script, never real terminal signals.

- `noctalia/gtk.nix` disables Stylix's GTK target, preserves fonts/icons/cursors and
  packages adw-gtk3. Do not reintroduce managed gtk-theme/color-scheme dconf keys.
- Keep both GTK CSS entrypoints declarative with the literal Noctalia import. Only
  `noctalia.css` is writable; `prepare_theme_output.py` seeds valid placeholders for
  both versions before linkGeneration. Never register runtime CSS as home.file.
- Disabling the Stylix GTK target removes its flattened fixed theme/Flatpak pin.
  Native GTK is covered; sandboxed-app integration remains separate.
- Keep built-in template enablement declarative; upstream GTK undo hooks try to edit
  managed gtk.css. Roll back through Nix, not GUI template undo.
- Newer Stylix gates cursor projection with each target. Native GTK/Xresources
  modules disable those color targets, so keep cursor settings explicit there via
  config.stylix.cursor. The theme invariants must continue checking cursor retention.

- `noctalia/qt.nix` owns Qt5ct/Qt6ct main configs; keep them declarative and select
  custom_palette with the separate writable Noctalia color path. Fusion honors
  QPalette; reintroducing Kvantum can bypass these colors.
- System Qt owns plugin installation/environment. Qt6ct accepts the existing qt5ct
  alias, tested using real offscreen Qt5/Qt6 probes. Do not add a competing env owner.
- The stock Qt template has no reload hook. Do not infer live reload from startup
  tests or expect Vicinae's independently managed theme to follow generic Qt colors.

- `noctalia/zed.nix` consumes the pinned community family verbatim and registers
  only Zed, not Gram. Keep opaque Noctalia Light/Dark selectors in native system mode.
  Disable Stylix's Zed target while preserving its font sizes/families explicitly.
- Preserve Zed's mutable HM settings merger; it owns theme/fonts but retains unrelated
  preferences. Only the separate runtime family is writable by Noctalia; no settings
  post-hook or custom reload process. Shared/Darwin Zed configuration is unaffected.

- `noctalia/zen-browser.nix` consumes upstream community CSS but must NOT run its
  apply.sh: it writes through Nix symlinks and scans old/backup profiles/user.js.
  Keep imports declarative in `.zen/default`; render separate persistent state CSS.
  Do not enable a duplicate Zen community catalog entry via GUI; its hook is unsafe.
- Enable toolkit.legacyUserProfileCustomizations.stylesheets via package policies,
  not privileged devtools or user.js. Keep the profile-aware launcher on the module's
  configured package so policies are actually bundled; raw flake packages bypass it.
- Zen may require restart for palette replacement; no browser restart automation.
  The shared/Darwin browser module is separate. Non-color new-tab sizing is retained.

- `noctalia/vscode.nix` installs the official pinned Noctalia VSIX declaratively.
  Only its theme JSON points to writable XDG state; never let templates write through
  the Nix-managed extension directory. Keep manifest/icon unchanged and settings managed.
- The upstream VS Code theme is single vs-dark even with light palette data. Document
  that limitation; don't fork the community template/manifest to hide it. Auto theme
  selection/updates are disabled; other extensions can still be installed manually.
- The VS Code module, not packages.nix, installs the app. Do not enable a duplicate
  community catalog entry using upstream's versioned mutable extension paths.

- `noctalia/lazygit.nix` uses the pinned community YAML with native LG_CONFIG_FILE
  layering (base first, theme second), not its config-rewriting apply.sh. Keep an
  empty gui map if needed so the managed base exists; runtime YAML stays separate.
- The package wrapper sets only a default file list, works with the unchanged Nu `lg`
  function and honors explicit native overrides. Don't add a global shell env owner,
  merge script or restart daemon. Never enable the duplicate community hook via GUI.
- PTY tests launch only isolated fixture repos, checking real RGB colors and config
  layering; they don't operate on the user's repository or prove live hot reload.

- `noctalia/fzf.nix` registers the upstream Bash snippet, not a custom Nu theme.
  `fzf-package.nix` sources it inside each child invocation, leaving parent options
  and keybindings alone. Keep programs.fzf.enable false; enabling it adds integrations.
- Shared packages reference programs.fzf.package; Darwin's default package remains
  unchanged. The NixOS wrapper preserves man pages and reads current XDG config.
- Existing FZF_DEFAULT_OPTS/options files and explicit CLI flags retain native
  precedence. New pickers read new colors; already-running pickers are not mutated.
  No Fish universal variables, shell eval hooks or custom color generators.

- `noctalia/niri.nix` appends an absolute optional include to niri-flake's default
  rendered document. Preserve the settings renderer; never replace the whole config
  with a color template. Niri 26.04 optional includes allow build validation without
  home files; the activation preparer normally ensures runtime output exists.
- Keep only layout/flags/bindings/rules in the managed Niri config, with colors in
  writable noctalia.kdl. Stock apply.sh recognizes the include and skips main writes.
  Validate full KDL plus generated output; optional=true doesn't ignore invalid data.
- Native include watching reloads colors. Never restart Niri or change focus-ring,
  border width, gaps, transparency or overview behavior as a theming side effect.

- Nushell has no entry in the pinned catalogs: `noctalia/nushell.nuon` is a small
  data-only input to Noctalia's native renderer, not a custom generator/service.
  It alone owns runtime nushell/theme.nuon; never restore bridge file copying.
- `noctalia/nushell-theme.nu` retains the mtime/pre-prompt reader, honors XDG state,
  preserves colors through partial/missing reads and advances cache only on success.
  Keep unrelated hooks/keybindings/shared/Darwin config unchanged; no source/eval of
  generated data. Old static light/dark NUON and env-stage copying are removed.

- `noctalia/starship.nix` composes the managed base with the verbatim built-in palette
  as a native input. STARSHIP_CONFIG points to a separate writable full runtime config
  because Starship has no include. No upstream config-writing hook/process scan.
- Preserve prompt format/modules and integration. Session and Nu env pointers must
  agree; open a fresh Nu session after migration. Keep runtime palette names out of
  the declarative base's palettes table to avoid duplicate TOML definitions.
- SwayOSD replacement is functional, not cosmetic: `noctalia/osd.nix` now selects
  native volume/brightness OSD and caps output at 100%. Don't alter Framework audio
  init/brightness DDC as incidental cleanup.

- `noctalia/btop.nix` uses the shipped btop template and fixed `noctalia` selector.
  Only the separate theme is writable; preserve the 1000ms update rate/default keys.
  Native SIGUSR2 reload is used by upstream. Unit hook tests mock pgrep/pkill; real
  reload tests may signal only their own sandbox child, never live user btop processes.

- `noctalia/emacs.nix` affects only Home Manager's plain-Emacs final package.
  Doom/Spacemacs wrappers bypass it and keep personal init/themes. Don't rewrite
  those profiles or assume an emacsclient daemon exists. Use the shipped theme
  at XDG state with startup loading, no global client hook.
- Preserve Emacs font/opacity source expressions. Batch tests prove Lisp/colors,
  not GUI font resolution. The upstream theme includes Org preferences; don't
  claim a color-only change or silently fork its settings.
- Lock/authentication policy remains independent of cosmetic theme work. Swaylock's
  fingerprint/lid-aware PAM is rollback-only; active routes are native. No real
  lock/suspend/authentication probes as the agent.

- Dormant Blender/Forge/gdu/gedit/Vencord/KDE generators are disabled in stylix.nix
  after package/config audit. Don't re-enable a global KDE palette/env overlay in
  this Niri/qtct setup by default. Keep native fonts/cursor/icons/Qt settings.
- Xresources is retained for installed xterm; `noctalia/xresources.nix` renders
  native color data, with static fonts/cursor and an include in the managed main.
  The xrdb merge hook is display-guarded; tests use only their own headless X server.
  Existing X11 windows may retain startup colors. Don't merge into a user display
  during preparation or call this existing-window hot reload.
- GTKSourceView retains the legacy stylix scheme ID (saved Gedit selection exists),
  but native Noctalia renders colors using the pinned upstream XML definitions.
  Keep syntax style definitions/lookup compatibility; don't rewrite app preferences.
  Out-of-store links expose one mutable XML; native v4/v5 manager tests are headless,
  not proof of GUI or v2/v3 behavior. Other selected schemes remain unchanged.
- Don't delete swaylock as an unused-file cleanup without review.
  Removing a declared env value doesn't rewrite old processes' inherited environment.

- Native password PAM and manual password/fingerprint passed; keyboard suspend and
  lid sleep/wake passed. Native-idle deployment and automatic sleep/key-wake are
  accepted. Live Caffeine/audio acquisition, native recognition and release passed;
  Caffeine-only six-minute idle suppression and release passed on the updated stack
  on 2026-10-23 (all three native actions suppressed, user confirms screen stayed on/
  unlocked). Independent full-duration audio suppression also passed that day,
  with no Caffeine and all three callbacks suppressed. The user's Mod+Shift+S
  guarded-suspend attempt produced Suspend Blocked while audio held sleep:block,
  without observed lock/sleep; user pause/release then passed at 14:56:45. This is
  the helper veto, not raw logind/all-panel enforcement. Reader-unavailable recovery,
  external outputs and separate power-button interaction are owner-deferred to
  [the backlog](../../docs/noctalia-backlog.md) (2026-10-23). Revisit on a relevant
  issue/request; do not repeatedly schedule them as mandatory next steps for ordinary
  cleanup. Deferred is not passed or full security acceptance; fallback/auth/policy
  retirement still needs separate explicit review.
  Native idle owns 300s lock, 305s screen_off/restore and 310s lock_and_suspend, with
  fade=0 and locked_timeout=0 to preserve elapsed timings. Keep swayidle disabled;
  do not introduce dummy hooks, a second scheduler or its old package patch.
- Native ScreenSaverService tracks logind BlockInhibited for the audio watcher;
  IdleManager also respects screensaver/Wayland inhibition and Caffeine. Preserve
  audio watcher, root fingerprint/lid management, tuned and lid holdoff. Source
  review does not replace live audio/Caffeine tests.
- Share niri/safe-suspend-package.nix across keyboard/native power callers and use
  its absolute store executable, not a bare profile command: restricted service
  PATH caused a real 310s command-not-found failure. Native lock-and-suspend uses
  the absolute --require-lock backend, which fails closed without a positive lock
  hint. Manual calls retain blocker/logind behavior. Never bypass inhibitors or
  mutate lock/power/fingerprint state as an agent.
- A strict-context native policy patch prevents plain-suspend's stale skip-lock flag
  from bypassing configured protection. Panel/native power uses lock-and-suspend/
  guarded helper. Keep swaylock/PAM installed only as rollback until acceptance.
- The upstream comment claiming fprint PAM filtering is stale; don't rely on it.
  Patch exact context (--fuzz=0); fingerprints are separately native D-Bus. Preserve
  TTY/login/sudo/polkit stacks and review account/fingerprint semantics before cutover.
  Never run real authentication, lock, fingerprint or suspend tests as the agent.

### Retained Niri/Umbriel sessions
- Owner chose to keep both installed/selectable for experimentation (2026-10-23).
  Niri stays the Greeter default; no automatic winner, uninstall or mandatory
  performance comparison. See docs/umbriel-trial.md and backlog NOC-04.
- Initial Umbriel session/basic smoke passed, not full lock/input/portal/power or
  return-session coverage. Native Alt+Tab is installed/user-confirmed working;
  passive checks found valid config reload with original service start times.
- Shared topbar UI can be discussed next; keep both overview protocols and existing
  behavior unless the owner requests a change. No UI redesign follows implicitly.

### Continuous floating bar
- Owner requested one shared background instead of individual widget islands while
  keeping one floating gap. Current config has capsule=false, opacity=1, top/side
  margins=16 and main-axis padding=12. Preserve widgets/fonts/clock/neutral text.
- bar-ipc-edge-slide.patch folds positive edge gaps into the native layer surface
  for IPC slides too. Keep reservation/panel math and visual/input geometry coherent;
  do not enable pointer/smart auto-hide to obtain this geometry or add a hot strip.
- User-accepted visual polish uses native border=outline, border_width=1, radius=16 and
  widget_spacing=12. Sysmon label_min_width is 48 for CPU/RAM and 56 for temperature:
  minima only, no clipping/hidden units/polling change. Widgets/font/clock/gaps and
  blur/shadow off stay. No additional patch; appearance accepted in the reported
  Umbriel session on 2026-10-23, not exhaustive values/fonts/scales/output coverage.
- Motion-first follow-up changes only explicit manual IPC exit to 100ms ease-out;
  entrance stays 200ms. User accepted the bar/motion on 2026-10-23; tray context-menu
  anchoring remains a distinct reported issue. Native call/easing expressions are
  probed, but no asynchronous tweak is a strict compositor synchronization guarantee.
  Visual polish was kept out of motion and requested separately afterward.
- Placement follow-up moves notifications after clock in center, retaining clock
  anchor/order of other widgets/toast policy. tray-menu-click-anchor.patch passes
  parent-surface-local click coordinates through the native DBusmenu callback;
  don't add output offsets, floating margins or DPI scaling again. Late pointer
  leave can otherwise force a zero anchor. Legacy app-owned ContextMenu/grab/parent
  behavior stays unchanged. User confirmed bell/menu placement in Umbriel on
  2026-10-23, corroborated by config/healthy services; don't infer every app, drawer,
  submenu, output or Niri case from that. Native repro/probes alone aren't live proof.
- Both overview adapters and no-reserved-space policy stay. Strict patch application,
  432-case actual native before/after geometry and style probes cover configuration,
  not visual acceptance. Native package rebuild may restart Noctalia during user
  activation: never apply/restart while locked. See docs/noctalia-topbar.md.

### Native wallpaper/backdrop
- `noctalia/wallpaper.nix` enables native wallpaper with crop/1s fade, but disables
  Noctalia's separate backdrop. Niri places `^noctalia-wallpaper$` within its backdrop:
  exactly one surface behind overview, never inside workspace previews. Enabling
  ordinary wallpaper plus a separate backdrop duplicates the image in workspaces.
- Native `started` and `theme_mode_changed` hooks call wallpaper-mode.sh, not the
  HM bridge. V5 directory modes do not immediately apply a fixed pair on mode change.
  The helper locks only its own runtime file, queries current resolved app mode
  under that lock (never trust stale event env), and uses bounded wallpaper-set IPC.
  It never waits for HM, builds/activates, writes mode/palette or restarts a service.
  Keep favorites path-only to avoid reverse palette/mode control. No rotation/poller.
- Native async hooks discard stdio: log selection/errors explicitly with bounded
  logger calls (tag noctalia-wallpaper-mode). Fail without guessing a mode/image;
  a later native startup/mode event reasserts the pair. No persistent retry service.
  Keep its registration/serialization/fake-IPC tests and the bridge non-ownership
  regression. Mode/image and shell-startup hooks passed during the user's unlocked
  rebuild on 2026-10-23; no shell restart on later mode changes. A fresh OS boot of
  this policy and external-output/reconnect appearance were not tested.
- Native Noctalia owns reconnects and wallpaper; the awww package/input and the
  legacy monitor-hotplug service were removed. Do not reintroduce either.
- No automatic process-kill hook. A Noctalia restart may briefly remove its wallpaper.

## Audio Gotchas

### Shell Volume Module
- Noctalia V5 uses its native audio service for the widget/control center.
- OSD belongs at bottom_center (horizontal and vertical) to avoid the topbar.
  Plain F1–F12 must reach apps; Framework Fn+Esc hardware Fn Lock selects media
  actions behind Fn. Don't emulate Fn in Niri or apply hid_apple fnmode to
  this AT keyboard. Existing external NuPhy mappings remain separate.
- Volume keys call native Noctalia IPC with 5% steps/mute. SwayOSD and the old
  volume cache producer/startup are removed; keep Framework pw-loopback init intact.
- Brightness still uses brightnessctl + async DDC. Only display calls native
  brightness-osd <actual%>; no second hardware adjustment. OSD failure must not
  block DDC, and internal control failure must not propagate stale values.
- Per-user brightness runtime state replaces shared /tmp paths. Tests mock all
  hardware; never test actual volume/brightness changes as the agent.
- The compatibility bridge must not restart retired SwayOSD/other native clients;
  remaining prebuilt consumers still need audit before bridge removal.

### Framework pw-loopback
- **Must start at session startup** for volume controls to work
- Without it, `wpctl set-volume` appears to work but doesn't change volume
- Configured in `niri/startup.nix` as spawn-at-startup

### Audio Keep-Alive (`audio-keep-alive/`)
- Prevents speaker amplifier pops (hardware limitation)
- Plays inaudible silence via `pacat` at 1% volume
- Minimal resource usage (~1.6MB, negligible CPU)
- Trade-off: ~0.1-0.3W extra power
- Check: `systemctl --user status audio-keep-alive`
- See: https://docs.kernel.org/sound/soc/pops-clicks.html

### QEMU Audio (Android Emulator)
- QEMU requests ~2.7ms latency causing buffer underruns
- Affects **all audio** when emulator runs
- Fix: `pulse.rules` forces higher latency for QEMU
- `monitor.alsa.rules` only matches hardware, NOT app streams
- See: https://github.com/wwmm/easyeffects/issues/2406

## Android Emulator Gotchas

### AMD GPU (Radeon 890M)
Environment variables required (set via `systemd.user.sessionVariables`):
- `VK_ICD_FILENAMES` - Must point to system Vulkan ICD
- `RADV_DEBUG=zerovram` - Fixes gray screen on RDNA 3.5 (gfx1150)

**Important:** `home.sessionVariables` does NOT work for GUI apps launched via greetd.

### AVD Configuration
- Android Studio creates AVDs with `hw.gpu.mode=auto` (doesn't work)
- Run `configure-avd` after creating AVDs to fix:
  - Sets `hw.gpu.mode=host`
  - Disables quickboot (required for hardware GPU)

Configuration in `android/`

## Power Management

### Power Profile Access
```bash
cat /sys/firmware/acpi/platform_profile  # low-power, balanced, performance
tuned-adm active  # Check active profile
```
Existing tuned Framework profiles are retained; do not enable power-profiles-daemon alongside tuned.

### ABM Toggle
- `Mod+Shift+B` runs `toggle-abm`
- Level 0: Accurate colors (photo editing)
- Level 3: Power savings (battery)
- Custom ABM/Stay On popup controls are not ported to Noctalia; the keybind/service remains.

## Desktop Gotchas

### Noctalia V5
- Pinned native C++ 5.3.0 via `inputs.noctalia`; do not use V4 QML settings/plugins.
- `programs.noctalia.checkConfig` validates TOML during builds. That does not guarantee
  custom palette JSON is runtime-valid: V5.3.0 also requires terminal color data.
  Prefer the shipped Catppuccin palette instead of an incomplete UI-only mapping.
- `noctalia-overview.service` bridges active Niri/Umbriel overview events to
  `bar-show`/`bar-hide`. Select by XDG_CURRENT_DESKTOP and its socket; never use a
  stale other-compositor socket. Umbriel subscribe keeps its write side open;
  Niri's EventStream/half-close behavior is unchanged. Unit conditions use OR
  socket checks plus Wayland. Keep strict overview-only behavior, not smart-hide.
- The Noctalia `started` hook restarts that watcher after IPC is ready. It is also
  wanted by graphical-session.target and idempotently started after reloadSystemd:
  reconciliation can stop PartOf dependents while the shell's restart is cancelled,
  so the started hook alone cannot recover it. Never restart the shell to fix this.
- Noctalia owns notifications and system-battery warnings (20%, native 5%/2% escalation).
  Dunst and `battery-notifications` are not imported; keep those inactive while native
  warnings are enabled. The old full-charge toast is not retained. Other managers remain.
- `noctalia/battery-warning-no-spam.patch` (checked by `checks.<system>.noctalia-battery-warning`)
  stops the two upstream repeat sources: startup no longer repeats the configured low level
  (critical 5%/2% still notify), and charging/unknown charge states suppress without re-arming
  `firedLevel` because the Framework EC reports `discharging`/`unknown` while AC is online.
  The system battery additionally requires UPower's aggregate `OnBattery`. Never restore a
  re-arm-on-charging step or `.value_or(false)` on the charge state; re-arming belongs only to
  the charge rising past every alert point. The check mirrors the sdbus UPower header in
  `noctalia/battery-warning-stubs/`; keep it in sync with upstream on input bumps.
- GUI overrides in `~/.local/state/noctalia/settings.toml` take precedence over Nix config.
- V5 plugins use Luau; review compatibility before enabling community plugins.
- `noctalia/plugins.nix` exports only pinned Udiskie Manager and Lid Guard plugins.
  Storage settings remain in `storage.nix`; keep the udiskie automounter and disable
  plugin notifications to avoid duplicates. Mutable community source is disabled
  while the curated `nix-reviewed` path source owns these plugins.
- Caffeine blocks idle; Lid Guard blocks only lid events and must be toggled on manually.
  Its transient `noctalia-lid-guard.service` can survive a shell/plugin restart; stop it
  explicitly to restore normal lid handling. Never assume Caffeine alone covers lids.
- `niri/safe-suspend.sh` queries structured logind inhibitors, blocks on high-level
  sleep/block locks, and fails closed on query/parse errors. It never uses a bypass flag.
  `checks.x86_64-linux.safe-suspend` tests this with fake commands, not real suspend.
- See `docs/noctalia-niri-overview.md` for troubleshooting and rollback.

### Profile-sync-daemon (`profile-sync-daemon.nix`)
- Syncs browser profiles to tmpfs (faster I/O, less SSD writes)
- **Zen Browser support via overlay** (`overlays/profile-sync-daemon.nix`)
- Resync every 10 minutes, keeps 3 backup snapshots
- **Close browser before first activation**
- Check: `systemctl --user status psd`, `psd preview`

### Vicinae Configuration
- App and build helpers pinned by the `vicinae` flake input (v0.29.2).
- Framework imports `inputs.vicinae.homeManagerModules.default`; use `programs.vicinae`
  and its systemd integration. `Mod+Space` runs `vicinae toggle`.
- Use `theme.light`/`theme.dark` and `launcher_window`; layer_shell stays disabled for Niri.
- `noctalia/vicinae.nix` consumes the pinned community TOML/apply.sh, not a fork.
- Both mode selectors must remain "noctalia" so native theme-set rescans/reloads
  without taking the settings-write branch. Keep Papirus and the HM override wrapper.
- Only `~/.local/share/vicinae/themes/noctalia.toml` is runtime-writable; don't declare
  it as home.file/xdg.dataFile or regenerate static Stylix colors.
- Native community apply.sh owns reload. The compatibility bridge must not restart
  Vicinae; settings and service units remain identical across specialisations.
- The real theme parser probe for Vicinae 0.29 needs src/lib/common/include as well
  as the server include paths. Keep the upstream parser test when source layout moves.
- Zed, Zen Browser, VS Code, lazygit and fzf also have community templates in the pin;
  audit and reuse those individually rather than writing custom replacements.
- GTK/Papirus stays in `stylix.nix`; generic Qt palettes/main configs live in `noctalia/qt.nix`.
- Stylix's Vicinae target is disabled; Bluetooth remains disabled due to its prior
  Node.js/usocket build issue.

## Module Locations

| Module | Purpose |
|--------|---------|
| `niri/` | Window manager (binds, layout, rules, startup, lid-switch) |
| `noctalia/` | Native V5 shell, palettes and overview IPC bridge |
| `noctalia/theme.nix` | Runtime mode hooks and temporary app-theme adapter |
| `stylix.nix` | Theming with specializations |
| `android/` | Emulator environment variables |
| `1password-session/` | Lock 1Password's SSH keys on suspend (auto-lock stays off) |
| `audio-keep-alive/` | Amplifier pop prevention |
| `battery-notifications/` | Legacy warning monitor (inactive; Noctalia owns alerts) |
| `profile-sync-daemon.nix` | Browser profile sync |
| `vicinae.nix` | Application launcher |
| `packages.nix` | User packages (GUI apps, dev tools) |
