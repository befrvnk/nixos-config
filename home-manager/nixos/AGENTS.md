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
Used in: `niri/layout.nix`. Noctalia uses its built-in Catppuccin palette and chooses
its own mode. The compatibility adapter selects the matching prebuilt app generation.

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
- App palettes still use Catppuccin until individual runtime templates replace Stylix outputs.

### Wallpaper Management (awww)
- awww-daemon starts at session startup (`niri/startup.nix`)
- Noctalia's theme adapter sends `awww img` on mode change/hotplug
- 1-second fade transitions
- Backdrop layer (visible in Niri overview)

## Audio Gotchas

### Shell Volume Module
- Noctalia V5 uses its native audio service for the widget/control center.
- Keyboard controls still use `niri/volume-ctl.sh` and SwayOSD; keep Framework sink init.
- The old volume cache is not read by Noctalia. Noctalia volume/brightness OSD is disabled.

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
- The Noctalia `started` hook starts that watcher only after IPC is ready.
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
- App and build helpers pinned by the `vicinae` flake input (v0.29.2)
- Framework imports `inputs.vicinae.homeManagerModules.default`
- Uses `programs.vicinae` and its user systemd integration
- Bound to `Mod+Space` in `niri/binds.nix` (`vicinae toggle`)
- Both theme modes use the generated `stylix` theme; Darkman try-restarts the service
- `launcher_window.layer_shell.enabled = false` for Niri compatibility
- GTK/Papirus and Qt5ct/Qt6ct configuration stays in `stylix.nix`, not `vicinae.nix`
- Stylix's built-in Vicinae target is disabled; the launcher module owns its theme
- Configuration in `vicinae.nix`; Bluetooth remains disabled due to its prior Node.js/usocket build issue

## Module Locations

| Module | Purpose |
|--------|---------|
| `niri/` | Window manager (binds, layout, rules, startup, lid-switch) |
| `noctalia/` | Native V5 shell, palettes and overview IPC bridge |
| `quickshell/` | Previous custom shell, retained but not imported |
| `noctalia/theme.nix` | Runtime mode hooks, app-theme adapter and wallpaper hotplug |
| `darkman/` | Legacy controller (not imported) |
| `stylix.nix` | Theming with specializations |
| `android/` | Emulator environment variables |
| `audio-keep-alive/` | Amplifier pop prevention |
| `battery-notifications/` | Legacy warning monitor (inactive; Noctalia owns alerts) |
| `profile-sync-daemon.nix` | Browser profile sync |
| `vicinae.nix` | Application launcher |
| `packages.nix` | User packages (GUI apps, dev tools) |
