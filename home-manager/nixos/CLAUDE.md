# NixOS Home-Manager Configuration

NixOS-specific user configuration including Wayland, systemd services, and Stylix theming.

## What Goes Here

- Window manager config (niri/)
- Status bar (ironbar/)
- Theme switching (darkman/, stylix.nix)
- User systemd services
- Wayland-specific apps
- Anything using `config.lib.stylix.colors`

## Theming System

### Stylix + Darkman Architecture
1. **System Stylix** (`modules/theming/stylix.nix`): Minimal base config
2. **Home-Manager Stylix** (`stylix.nix`): Full theming with specializations
3. **Darkman**: Time-based light/dark switching

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
Used in: `ironbar/default.nix`, `niri/layout.nix`

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

### Theme Switching (Darkman)
`darkman-switch-mode.sh` handles:
- Systemd environment variables
- Niri socket commands for appearance
- awww wallpaper changes
- dconf settings for GTK apps

**Important:** Check `DARKMAN_RUNNING` env var to prevent infinite loops.

### Wallpaper Management (awww)
- awww-daemon starts at session startup (`niri/startup.nix`)
- Darkman sends `awww img` on theme change
- 1-second fade transitions
- Backdrop layer (visible in Niri overview)

## Audio Gotchas

### Ironbar Volume Module
- **Do NOT** use built-in volume module (crashes with PulseAudio)
- Use custom wpctl-based script in `ironbar/modules/volume/`

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
Ironbar battery popup uses `tuned-adm` for switching.

### ABM Toggle
- `Mod+Shift+B` runs `toggle-abm`
- Level 0: Accurate colors (photo editing)
- Level 3: Power savings (battery)
- Ironbar display popup has ABM and Stay On buttons

## Desktop Gotchas

### Niri Overview Popups
- `niri-overview-watcher` service closes Ironbar popups on overview exit
- Without it, popups remain visible after returning to desktop
- Service in `ironbar/modules/niri-overview-watcher/`

### Profile-sync-daemon (`profile-sync-daemon.nix`)
- Syncs browser profiles to tmpfs (faster I/O, less SSD writes)
- **Zen Browser support via overlay** (`overlays/profile-sync-daemon.nix`)
- Resync every 10 minutes, keeps 3 backup snapshots
- **Close browser before first activation**
- Check: `systemctl --user status psd`, `psd preview`

### Vicinae Configuration (v0.17+)
- Config uses `theme.light` and `theme.dark` objects, NOT `theme.name`
- Use `launcher_window` for window settings, NOT `window`
- Stylix generates `~/.local/share/vicinae/themes/stylix.toml`
- Both modes use "stylix" theme; colors from regenerated file
- Darkman just restarts vicinae service
- Configuration in `vicinae.nix`

## Module Locations

| Module | Purpose |
|--------|---------|
| `niri/` | Window manager (binds, layout, rules, startup) |
| `ironbar/` | Status bar with modular scripts |
| `darkman/` | Theme switching, monitor hotplug |
| `stylix.nix` | Theming with specializations |
| `android/` | Emulator environment variables |
| `audio-keep-alive/` | Amplifier pop prevention |
| `battery-notifications/` | Low battery alerts |
| `profile-sync-daemon.nix` | Browser profile sync |
| `vicinae.nix` | Application launcher |
| `packages.nix` | User packages (GUI apps, dev tools) |
