# NixOS Home-Manager Configuration

NixOS-specific user configuration including Wayland, systemd services, and Stylix theming.

## What Goes Here

- Window manager config (niri/)
- Desktop shell (noctalia/, native C++ V5; quickshell/ retained for rollback)
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
  drives a oneshot worker. Do not change these to restart a worker mid-activation.
- Worker reads `theme-mode-get`; it never writes a mode or portal preference back.
  It requests native `templates-apply` after HM activation so Noctalia owns preference sync.
- Stylix's GNOME target is disabled: it writes `default` for light mode and would fight
  Noctalia. Static app fonts are preserved explicitly; do not reintroduce an HM-managed
  `org/gnome/desktop/interface.color-scheme` key.
- Normal HM activation and the worker share `$XDG_RUNTIME_DIR/noctalia-theme/activation.lock`.
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
  extended inhibited-idle, reader-unavailable recovery, external outputs and separate
  power-button interaction remain open. Do not silently claim full security acceptance.
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

### Native wallpaper/backdrop
- `noctalia/wallpaper.nix` enables native wallpaper with crop/1s fade, but disables
  Noctalia's separate backdrop. Niri places `^noctalia-wallpaper$` within its backdrop:
  exactly one surface behind overview, never inside workspace previews. Enabling
  ordinary wallpaper plus a separate backdrop duplicates the image in workspaces.
- The existing bridge retains only deterministic light/dark image selection via
  `wallpaper-set`; V5 directory modes don't directly apply this fixed pair. Keep
  favorites path-only to avoid reverse palette/mode control.
- Native Noctalia owns reconnects; no custom monitor-hotplug service/script or active
  awww startup/package remains. The old loose awww daemon can survive a rebuild:
  verify native surfaces before one-time official shutdown. Never kill it beforehand.
- No automatic process-kill hook. Inactive rollback code/input remain until cleanup.
  A Noctalia restart may briefly remove its wallpaper.

## Audio Gotchas

### Shell Volume Module
- Noctalia V5 uses its native audio service for the widget/control center.
- OSD belongs at bottom_center (horizontal and vertical) to avoid the topbar.
  Plain F1–F12 must reach apps; Framework Fn+Esc hardware Fn Lock selects media
  actions behind Fn. Don't emulate Fn in Niri/keyd or apply hid_apple fnmode to
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
- `noctalia-overview.service` bridges Niri overview events to `bar-show`/`bar-hide`.
- The Noctalia `started` hook restarts that watcher after IPC is ready. It is also
  wanted by graphical-session.target and idempotently started after reloadSystemd:
  reconciliation can stop PartOf dependents while the shell's restart is cancelled,
  so the started hook alone cannot recover it. Never restart the shell to fix this.
- Noctalia owns notifications and system-battery warnings (20%, native 5%/2% escalation).
  Dunst and `battery-notifications` are not imported; keep those inactive while native
  warnings are enabled. The old full-charge toast is not retained. Other managers remain.
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
| `quickshell/` | Previous custom shell, retained but not imported |
| `noctalia/theme.nix` | Runtime mode hooks and temporary app-theme adapter |
| `darkman/` | Legacy controller (not imported) |
| `stylix.nix` | Theming with specializations |
| `android/` | Emulator environment variables |
| `audio-keep-alive/` | Amplifier pop prevention |
| `battery-notifications/` | Legacy warning monitor (inactive; Noctalia owns alerts) |
| `profile-sync-daemon.nix` | Browser profile sync |
| `vicinae.nix` | Application launcher |
| `packages.nix` | User packages (GUI apps, dev tools) |
