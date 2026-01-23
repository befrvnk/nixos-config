# NixOS Configuration Agent Guidelines

## Build & Test Commands

**Important:** This configuration uses [nh](https://github.com/nix-community/nh) (Nix Helper) instead of `nixos-rebuild`. Always prefer `nh` commands for better output, faster builds, and visual diffs.

**Note for AI Agents:** Do NOT run any commands requiring `sudo`. If a task requires sudo privileges, inform the user and ask them to run the command manually. The commands below are documented for reference only.

### Primary Commands (use these)
- **Rebuild system:** `rebuild switch` (when in devenv) or `nh os switch ~/nixos-config`
- **Test without activating:** `nh os test ~/nixos-config` (builds but doesn't set as boot default)
- **Update and rebuild:** `nix flake update && rebuild switch` (updates flake.lock and rebuilds)
- **Clean old generations:** `nh clean all --keep 5` (keeps last 5 generations)
- **Search packages:** `nh search <package-name>`

**Note:** The `rebuild` script is available when the devenv environment is active (automatic via direnv).

### Additional Commands
- **Check flake validity:** `check` (in devenv) or `nix flake check --accept-flake-config`
- **Format code:** `nix fmt` (auto-formatted on commit via pre-commit hooks)
- **Update flakes manually:** `nix flake update --accept-flake-config`
- **Dry-run build:** `nix build .#nixosConfigurations.framework.config.system.build.toplevel --dry-run --accept-flake-config`

**Note:** The `--accept-flake-config` flag trusts the flake's cachix configuration. Devenv scripts include this flag automatically.

### Legacy Commands (avoid these)
- ❌ `nixos-rebuild switch` → Use `nh os switch` instead
- ❌ `nixos-rebuild test` → Use `nh os test` instead
- ❌ `nix-collect-garbage` → Use `nh clean all` instead

### Commands Requiring User Intervention (DO NOT RUN)

**AI Agents must NOT execute these commands.** Document them in responses and ask the user to run them manually:

- **Rollback to previous generation:** `sudo nixos-rebuild switch --rollback`
- **List all generations:** `sudo nix-env --list-generations --profile /nix/var/nix/profiles/system`
- **Boot into specific generation:** `sudo nixos-rebuild switch --rollback --generation <number>`
- **Hardware scans:** `sudo nixos-generate-config --show-hardware-config`
- **Systemd system services:** `sudo systemctl <start|stop|restart|status> <service>`
- **Any command with sudo:** Inform the user and provide the command for them to run

### Safe Commands for Agents

Agents CAN safely run these commands without sudo:

- **devenv scripts (preferred):** `rebuild switch`, `rebuild`, `check`, `sysinfo`, `generations`, `flake-update`
- **All nh commands:** `nh os switch ~/nixos-config`, `nh os test ~/nixos-config`, `nh clean all`, etc.
- **Nix commands:** Always use `--accept-flake-config` flag:
  - `nix flake check --accept-flake-config`
  - `nix flake update --accept-flake-config`
  - `nix build --accept-flake-config`
  - `nix fmt` (no flag needed)
- **Git operations:** `git add`, `git commit`, `git push`, `git status`, etc.
- **User systemd services:** `systemctl --user status/start/stop/restart <service>`
- **Development tools:** `deadnix`, `nixfmt`, `shellcheck`, `statix` (when in devenv environment)
- **File operations:** Read, Edit, Write tools for configuration files
- **Directory operations:** `ls`, `tree`, `fd`, file searches

**Important for Agents:** Prefer devenv scripts over raw nix commands. Devenv scripts automatically include the correct flags and provide better output.

## Code Style Guidelines
- **Formatting:** Uses `nixfmt` (RFC style) - automatically applied via pre-commit hooks
- **File structure:** Modular organization with clear separation (modules/, home-manager/, hosts/)
- **Imports:** Use relative imports within modules, absolute paths for cross-module imports
- **Naming:** kebab-case for files, camelCase for variables where appropriate
- **Comments:** Minimal inline comments, prefer self-documenting code
- **Error handling:** Use proper Nix attribute set validation and default values
- **Sorting:** Always sort imports and lists alphabetically for consistency and easier diffs
- **Script externalization:** Never inline scripts longer than 5 lines in Nix files. Write them to separate `.sh` files and load with `builtins.readFile` or `pkgs.replaceVars`
- **Explicit PATH in scripts:** Always use `pkgs.writeShellScript` with explicit PATH exports, never assume tools are in PATH
- **Attribute set merging:** Prefer `lib.mkMerge` over inline merging when combining multiple attribute sets for readability

## Development Workflow
- direnv automatically loads devenv environment on directory entry
- Pre-commit hooks (via devenv) ensure all committed code is formatted
- Use `rebuild switch` (from devenv) for convenient system rebuilding
- Test changes with `nh os test ~/nixos-config` before committing to ensure they work
- Use `nix flake update && rebuild switch` to update flakes and rebuild in one command
- Clean old generations periodically with `nh clean all --keep 5`

### Code Quality and Testing

**Conditional testing based on file types:**
- **Nix files modified:** Run `nh os test ~/nixos-config` or `nix flake check --accept-flake-config`
- **Shell scripts only:** Skip Nix testing, just validate scripts
- **Documentation only:** No testing needed

**Linting and validation:**
- **After modifying Nix files:** Run `statix check .` to catch common issues, fix any warnings
- **After modifying shell scripts:** Run `shellcheck <script>` to validate syntax and catch bugs
- **Before commits:** Run `nix fmt` to format all Nix files

**Testing scripts before manual testing:**
- **Always test scripts by running them** when possible to catch errors early
- For display/status scripts (e.g., ironbar modules): Run directly and verify output
- For scripts with controlled input: Test with sample data
- For complex scripts: Copy and run individual sections in bash to verify behavior
- This saves significant time by catching issues before full system rebuild

### Standard Development Process
1. **Check existing documentation** - Review README.md and docs/ for related content
2. **Make changes** to configuration files
3. **Test** with `nh os test ~/nixos-config` to verify it builds
4. **Update documentation** (README.md and/or docs/) if needed
5. **Apply changes** with `rebuild switch`
6. **Verify** the system behaves as expected
7. **Commit** with descriptive message explaining what and why
8. **Push** to remote repository

**Important:** Always update documentation BEFORE committing. This ensures documentation stays in sync with code changes.

### Documentation Checklist for Commits

Before committing, ask yourself:
- [ ] Does README.md need updating? (packages, features, shortcuts, etc.)
- [ ] Do existing docs/ files need updating?
- [ ] Should I create new documentation for this change?
- [ ] Are there quirks or workarounds that should be documented?
- [ ] Did I remove outdated information from documentation?

## Why nh (Nix Helper)?

This project uses [nh](https://github.com/nix-community/nh) as a wrapper around NixOS/home-manager commands. Benefits:

- **Better output:** Colored, structured progress output with build summaries
- **Faster builds:** Automatic specialization detection and optimized rebuild paths
- **Visual diffs:** Shows package changes before/after rebuild
- **Simpler commands:** Auto-detects hostname and config location
- **Safer garbage collection:** `nh clean` provides better control over generation cleanup
- **Unified interface:** Single tool for OS, home-manager, and package management

**When to use what:**
- System rebuilds: `rebuild switch` (in devenv) or `nh os switch ~/nixos-config` (not `nixos-rebuild`)
- Flake validation: `check` (in devenv) or `nix flake check --accept-flake-config`
- Home-manager: Integrated with system rebuild (no separate command needed)
- Package search: `nh search` (alternative to `nix search`)
- Cleanup: `nh clean all --keep N` (not `nix-collect-garbage`)
- Flake updates: `nix flake update --accept-flake-config`
- Formatting: `nix fmt`

## Project Structure

### Directory Organization
```
nixos-config/
├── flake.nix              # Entry point - inputs, outputs, overlays
├── hosts/                 # Host-specific configurations
│   └── framework/         # Framework laptop config
│       ├── default.nix    # Host config
│       ├── hardware-configuration.nix  # Auto-generated
│       └── home.nix       # Home-manager integration
├── modules/               # System-level NixOS modules
│   ├── default.nix        # Central import file
│   ├── users.nix          # User account definitions
│   ├── desktop/           # Display manager, compositor
│   ├── hardware/          # Hardware-specific (fprintd, power, keyboard)
│   ├── services/          # System services (darkman, pipewire, bluetooth)
│   ├── system/            # Core settings (boot, networking, packages)
│   └── theming/           # System-level stylix config
├── home-manager/          # User-level configurations
│   ├── frank.nix          # Main user config (imports all)
│   ├── packages.nix       # User application packages
│   ├── stylix.nix         # Theming with specializations
│   ├── niri/              # Window manager (split by concern)
│   ├── ironbar/           # Status bar (modular scripts)
│   └── */                 # Other app configs
├── overlays/              # Package modifications
└── docs/                  # Detailed documentation
```

### Module Import Patterns

**System modules:** `modules/default.nix` acts as central import point
- Each host imports this single file
- Organized by category: core, users, system, hardware, desktop, services, theming

**Home-Manager modules:** `home-manager/frank.nix` imports all user modules
- Complex apps get directories (niri/, ironbar/, darkman/)
- Simple configs are single files (git.nix, ssh.nix, nushell.nix)
- Each module is self-contained

## System vs Home-Manager Split

**System Level** (`modules/`): Root-level, affects all users
- Boot configuration (LUKS, TPM2, secure boot)
- Hardware drivers and firmware
- System services (greetd, darkman daemon, pipewire)
- Network management, power management
- Security (PAM, polkit, TPM)
- System users and groups

**Home-Manager Level** (`home-manager/`): User-specific customization
- User applications and packages
- Shell configuration (nushell, starship, atuin, carapace)
- Application settings (git, ssh, editors)
- Window manager keybindings and rules
- Desktop environment (ironbar, vicinae, dunst)
- User services (stasis idle manager, battery notifications)
- Theming specializations (dark/light modes)

**Package Split:**
- System packages: `modules/system/packages.nix` (git, vim, wget, core tools)
- User packages: `home-manager/packages.nix` (GUI apps, dev tools, CLI tools)

## Common Configuration Patterns

### Script Embedding Pattern
Scripts are embedded using `pkgs.writeShellScript`:
```nix
let
  myScript = pkgs.writeShellScript "script-name" ''
    export PATH="${pkgs.foo}/bin:${pkgs.bar}/bin:$PATH"
    ${builtins.readFile ./script.sh}
  '';
in
{
  systemd.user.services.my-service = {
    Service.ExecStart = "${myScript}";
  };
}
```

Or with variable replacement:
```nix
home.file.".local/share/script.sh" = {
  source = pkgs.replaceVars ./script.sh {
    tool = "${pkgs.tool}";
    path = "${some.path}";
  };
  executable = true;
};
```

### Stylix Color Injection Pattern
Access Stylix colors via `config.lib.stylix.colors`:
```nix
{ config, ... }:
let
  colors = config.lib.stylix.colors;
in
{
  # Example: Generate CSS with color variables
  xdg.configFile."app/style.css".text = ''
    @define-color base00 #${colors.base00};
    @define-color base01 #${colors.base01};
  '';
}
```

Used in: `ironbar/default.nix`, `niri/layout.nix`

### Modular Splitting by Concern
Complex configurations split into multiple files:
```nix
# default.nix - Entry point
{ lib, ... }:
{
  imports = [
    ./binds.nix
    ./layout.nix
    ./rules.nix
  ];

  programs.app.settings = lib.mkMerge [
    # Settings from imported modules merge here
  ];
}
```

Examples: `home-manager/niri/`, `home-manager/ironbar/`

### Specialization Pattern (Theme Switching)
Enable theme switching without full rebuilds:
```nix
{
  stylix = { ... };  # Base configuration

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

See: `home-manager/stylix.nix`

### Shared Resource Pattern
Define shared resources once, import everywhere:
```nix
# home-manager/wallpapers/default.nix
{
  light = ./mountain.jpg;
  dark = ./mountain_dark.jpg;
}
```

Imported in: `stylix.nix`, `darkman/default.nix`

### Event Monitoring Service Pattern
For services that watch system events (monitor hotplug, overview mode changes):
```nix
let
  watcherScript = pkgs.writeShellScript "event-watcher" ''
    # Event monitoring logic (e.g., udevadm monitor, niri event-stream)
    udevadm monitor --udev --subsystem-match=drm | while read -r line; do
      if echo "$line" | grep -q "change"; then
        sleep 2  # Debounce
        some-action
      fi
    done
  '';
in
{
  systemd.user.services.my-watcher = {
    Unit = {
      Description = "Event watcher service";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${watcherScript}";
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
```

Used in: `darkman/default.nix` (monitor-hotplug), `ironbar/modules/niri-overview-watcher/`

### Power Profile Access Pattern (tuned + Direct Sysfs)
Power profiles are managed by tuned with tuned-ppd providing PPD API compatibility.
AC/battery auto-switching is handled by tuned via upower events (not udev).

Direct sysfs access is still available for manual override:
```bash
# Get current profile
cat /sys/firmware/acpi/platform_profile
# Returns: low-power, balanced, or performance

# Set profile (world-writable via platform-profile-permissions service)
echo "balanced" > /sys/firmware/acpi/platform_profile

# Check active tuned profile
tuned-adm active
```

Used in: `home-manager/ironbar/modules/battery/` for manual profile switching in status bar.
AC/battery auto-switching handled by tuned in `modules/hardware/power-management.nix`.

### ABM (Adaptive Backlight Management)
AMD panel power savings via sysfs:
```bash
# Read current ABM level (0-4, higher = more savings)
cat /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings

# Set ABM level (done by tuned profile scripts on AC/battery change)
echo 3 > /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings
```
- Level 0: Disabled (accurate colors, for photo editing)
- Level 3: Aggressive (used on battery for power savings)
- Toggle: `Mod+Shift+B` runs `toggle-abm` command
- Ironbar display popup has ABM and Stay On toggle buttons

## Adding New Modules

### Simple Module (single file)
1. Create `home-manager/new-app.nix` or `modules/category/new-app.nix`
2. Import in `frank.nix` or `modules/default.nix`:
   ```nix
   imports = [ ./new-app.nix ];
   ```

### Complex Module (directory)
1. Create directory structure:
   ```
   home-manager/new-app/
   ├── default.nix        # Entry point
   ├── config.yaml        # Config files
   └── script.sh          # Scripts
   ```
2. Import in `frank.nix`: `imports = [ ./new-app ];`

### Adding Packages
- **System package:** Add to `modules/system/packages.nix`, then run `rebuild switch`
- **User package:** Add to `home-manager/packages.nix`, then run `rebuild switch`
- **Custom package:** Create overlay in `overlays/`, then run `rebuild switch`
- **Test first:** Use `nh os test ~/nixos-config` to verify the package builds before switching

### Creating User Services
```nix
systemd.user.services.my-service = {
  Unit = {
    Description = "My service";
    After = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${myScript}";
    Restart = "always";
    RestartSec = "10";
  };
  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};
```

**After creating the service:**
1. Test the configuration: `nh os test ~/nixos-config`
2. Apply the changes: `rebuild switch`
3. Check service status: `systemctl --user status my-service` (user services don't need sudo)

## Security Considerations

### PAM Configuration Pattern
Fingerprint authentication uses structured PAM rules:
```nix
security.pam.services.sudo = {
  rules.auth.fprintd = {
    order = 11400;  # Before unix auth (12000)
    control = "sufficient";
    modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
    args = ["timeout=10" "max-tries=3"];
  };
};
```

Applied to: sudo, login, greetd, swaylock, polkit-1

See: `modules/hardware/fprintd/default.nix`

### Keyring Management
- gnome-keyring is managed by PAM in `modules/desktop/greetd.nix`
- **Do NOT enable** `services.gnome-keyring.enable` in home-manager
- Use `lib.mkForce false` to override defaults

### Secure Boot & Encryption
- Lanzaboote handles secure boot integration
- LUKS with TPM2 auto-unlock configured in `hardware-configuration.nix`
- 1Password integration via polkit

### Firewall Configuration
- Enabled in `modules/system/security.nix`
- **Incoming traffic**: Blocked by default
- **Outgoing traffic**: Allowed
- **Localhost**: Always allowed (dev servers work without configuration)
- To open ports for LAN access: add to `allowedTCPPorts` or `allowedUDPPorts`

### Kernel Security Hardening
Configured in `modules/system/security.nix`:
- `kernel.dmesg_restrict = 1` - Kernel logs root-only
- `kernel.sysrq = 0` - Disable Magic SysRq key
- `kernel.yama.ptrace_scope = 1` - Restrict process debugging
- Network hardening: disable IP forwarding, ignore ICMP redirects, enable SYN cookies

See: `docs/security-hardening.md` for full details

## Theming System

### Three-Layer Architecture
1. **System-level Stylix** (`modules/theming/stylix.nix`): Minimal base config
2. **Home-Manager Stylix** (`home-manager/stylix.nix`): Full theming with specializations
3. **Darkman Integration**: Time-based light/dark switching

### Wallpaper Management (awww)
- awww-daemon runs continuously (started in `niri/startup.nix`)
- Darkman sends `awww img` command on theme change
- 1-second fade transitions between wallpapers
- Placed on backdrop layer (visible in Niri overview mode)

### Theme Switching
Darkman script (`darkman-switch-mode.sh`) handles:
- Systemd environment variables
- Niri socket commands for appearance
- awww wallpaper changes
- dconf settings for GTK apps

Prevents infinite loops with `DARKMAN_RUNNING` environment variable check.

## Common Gotchas

### Ironbar Volume Module
- **Do NOT** use built-in volume module (crashes with PulseAudio)
- Use custom wpctl-based script in `ironbar/modules/volume/`

### Darkman Activation
- Check `DARKMAN_RUNNING` to prevent infinite loops
- Wait for awww-daemon to be ready before sending commands

### USB Autosuspend
- Exclude `usbhid` devices to prevent input lag
- Configured in `modules/hardware/power-management.nix`

### Hardware Configuration
- `hardware-configuration.nix` is auto-generated - don't manually edit
- Host-specific overrides go in `hosts/framework/default.nix`

### State Versions
- System: `25.05`, Home: `25.05`
- **Never change** after initial setup

### Framework Audio pw-loopback
- The `pw-loopback` process **must start at session startup** for volume controls to work
- Without it, `wpctl set-volume` commands appear to work but don't change actual volume
- Configured in `home-manager/niri/startup.nix` as spawn-at-startup

### Stasis Idle Manager
- **Requires `input` group** for activity detection via libinput
- Without `input` group, idle timer doesn't reset on mouse/keyboard activity
- **Requires `pactl`** (pulseaudio package) for media detection
- Must be started via Niri `spawn-at-startup` (not systemd service) for proper Wayland access
- Configuration uses RUNE language with `default:` block at top level
- `inhibit_apps` uses exact Wayland app_id (e.g., `"zen-beta"` not `"zen"`)
- Check status with `stasis info`, manual control with `stasis pause/resume/toggle-inhibit`
- Replaces swayidle + wayland-pipewire-idle-inhibit
- Configuration in `home-manager/stasis.nix`

### Android Emulator (QEMU) Audio
- QEMU requests extremely low latency (~2.7ms / 118 samples at 44.1kHz) causing buffer underruns
- This affects **all audio** (Spotify, YouTube, etc.) when the emulator is running
- Fix uses `pulse.rules` in `pipewire-pulse.conf` to force higher latency for QEMU specifically
- **Important:** `monitor.alsa.rules` only matches hardware devices, NOT application streams
- QEMU uses PulseAudio compatibility layer, so it must be configured via `pulse.rules`
- 44.1kHz added to `allowed-rates` to avoid resampling when only QEMU is playing
- Global quantum increased (`min-quantum=1024`, `quantum=2048`) for additional stability
- See: https://github.com/wwmm/easyeffects/issues/2406

### Android Emulator GPU (AMD Radeon 890M)
- Android emulator requires specific environment variables for AMD GPU hardware acceleration
- `VK_ICD_FILENAMES` must point to system Vulkan ICD, otherwise emulator fails with `VK_ERROR_INCOMPATIBLE_DRIVER`
- `RADV_DEBUG=zerovram` fixes gray screen issue on RDNA 3.5 GPUs (gfx1150)
- Variables set via `systemd.user.sessionVariables` in `home-manager/android/default.nix`
- **Important:** `home.sessionVariables` does NOT work for GUI apps launched via greetd
- AVDs created in Android Studio use `hw.gpu.mode=auto` which doesn't work reliably
- Run `configure-avd` after creating AVDs to set `hw.gpu.mode=host` and disable quickboot
- Quickboot must be disabled for hardware GPU mode to work
- Configuration in `home-manager/android/`

### PipeWire Sample Rate Switching
- PipeWire supports both 44.1kHz (Spotify, QEMU) and 48kHz (YouTube, system sounds)
- Rate switching can cause crackling without proper ALSA buffer configuration
- Large `api.alsa.headroom` (8192) and `api.alsa.period-size` (1024) prevent crackling
- Quantum settings: `quantum=2048`, `min-quantum=1024`, `max-quantum=4096`
- `link.max-buffers=128` (default 16 is too low and causes crackling)
- Configuration in `modules/services/pipewire.nix`
- See: https://bbs.archlinux.org/viewtopic.php?id=280654

### Power Profiles (tuned with PPD compatibility)
- **tuned** manages power profiles with **tuned-ppd** providing PPD API compatibility
- `powerprofilesctl` still works (talks to tuned-ppd D-Bus API)
- **tuned handles AC/battery auto-switching** via upower events (not udev, minimal CPU overhead)
- Custom profiles `framework-battery` and `framework-ac` in `modules/hardware/power-management.nix`
- `platform-profile-permissions` service makes sysfs writable (kept for compatibility)
- Battery mode: low-power profile, EPP=power, boost OFF, WiFi power save ON, ABM level 3
- AC mode: balanced profile, EPP=balance_performance, boost ON, WiFi power save OFF, ABM disabled
- Ironbar battery popup uses `tuned-adm` for profile switching (applies all settings)
- USB autosuspend enabled (except HID devices) via udev rules
- Audio power save disabled (causes DBUS spam with pipewire)
- ZRAM with zstd compression enabled for memory pressure (see `modules/system/core.nix`)

### ABM (Adaptive Backlight Management)
- ABM reduces power by trading color accuracy for brightness
- `Mod+Shift+B` toggles ABM via `toggle-abm` command
- When disabled: ABM set to 0 (accurate colors for photo editing)
- When enabled: ABM set to level 3 (power savings)
- AC/battery auto-switching handled by tuned profile scripts (minimal CPU overhead)

### Niri Overview Popups
- A dedicated watcher service closes Ironbar popups when exiting overview mode
- Without it, popups opened during overview remain visible after returning to desktop
- Service: `niri-overview-watcher` in `home-manager/ironbar/modules/niri-overview-watcher/`

### SCX Scheduler
- Uses `scx_lavd` BPF scheduler with `--autopower` for adaptive power management
- Autopower mode automatically switches between powersave/balanced/performance based on EPP
- Requires `amd_pstate=active` kernel parameter to read Energy Performance Preference (EPP)
- Core Compaction: When CPU < 50% usage, active cores run faster while idle cores sleep
- Service managed by systemd: `systemctl status scx`
- Configuration in `modules/services/scx.nix`
- **CachyOS kernel** provides best sched_ext/scx_lavd integration (via xddxdd/nix-cachyos-kernel flake)

### CachyOS-Style Optimizations
Sysctl and kernel parameters based on [CachyOS Settings](https://github.com/CachyOS/CachyOS-Settings):
- **vm.swappiness = 180**: High value optimized for ZRAM (prefers compressed swap over dropping file cache)
- **vm.vfs_cache_pressure = 50**: Preserves directory/inode cache longer for better file performance
- **vm.dirty_bytes/dirty_background_bytes**: Fixed 256MB/64MB thresholds for predictable I/O
- **vm.page-cluster = 0**: Single-page swap reads optimal for ZRAM/SSD
- **net.core.netdev_max_backlog = 4096**: Larger network queue prevents packet drops
- **fs.file-max = 2097152**: High file handle limit for browsers/dev servers
- **kernel.kptr_restrict = 2**: Security hardening (hides kernel pointers)
- **rcutree.enable_rcu_lazy=1**: 5-10% power savings at idle via batched RCU callbacks
- **THP defer+madvise**: Reduces latency spikes from memory compaction
- **I/O scheduler**: `none` for NVMe (optimal), `mq-deadline` for SATA SSDs
- Sysctl settings in `modules/system/core.nix`, kernel params in `modules/hardware/power-management.nix`

### systemd-oomd (Out-of-Memory Daemon)
- Proactively kills processes under memory pressure before kernel OOM killer triggers
- Works with ZRAM: high swappiness (180) fills ZRAM first, oomd acts at 90% swap usage
- Enabled for both user slices (desktop apps) and system slice (services)
- 20-second memory pressure duration before action (Fedora default, prevents false positives)
- Configuration in `modules/services/oomd.nix`
- Check status: `systemctl status systemd-oomd`
- View kills: `journalctl -u systemd-oomd`

### Profile-sync-daemon (psd)
- Syncs browser profiles to tmpfs (RAM) for reduced SSD writes and faster I/O
- **Zen Browser support added via overlay** in `overlays/profile-sync-daemon.nix`
  - psd only reads browser definitions from its package directory, not user config
  - Overlay patches the package to include Zen browser definition
- Reads profile paths from `~/.zen/profiles.ini` (same format as Firefox)
- Resync timer runs every 10 minutes (configurable in `home-manager/profile-sync-daemon.nix`)
- Crash recovery: keeps last 3 backup snapshots
- **Close browser before first activation** to ensure clean sync
- Check status: `systemctl --user status psd`
- Preview sync targets: `psd preview`
- Configuration in `home-manager/profile-sync-daemon.nix`

### Vicinae Configuration (v0.17+)
- Config structure uses `theme.light` and `theme.dark` objects, NOT `theme.name`
- Use `launcher_window` for window settings, NOT `window`
- Stylix auto-generates `~/.local/share/vicinae/themes/stylix.toml` with current polarity colors
- Both light/dark modes use "stylix" theme; colors come from the regenerated theme file
- Darkman just restarts vicinae service - no need to patch settings.json
- Configuration in `home-manager/vicinae.nix`

## Path References
- **Nix store paths:** `${pkgs.tool}/bin/tool`
- **Relative imports:** `./file.nix` (within same directory)
- **Cross-module imports:** `../../path/to/module`
- **Home directory:** Use `~` in scripts, `$HOME`, or `config.home.homeDirectory`

## Module System Usage
- **lib.mkForce** - Override with highest priority
- **lib.mkDefault** - Set with lowest priority
- **lib.mkMerge** - Merge multiple attribute sets
- **lib.mkIf** - Conditional configuration
- **lib.mkBefore/mkAfter** - Order list items

## Git Commit Conventions

### Commit Message Format

```
<type>: <short summary in present tense>

<optional detailed explanation of what and why>
<include context, reasoning, and any quirks>

<optional references to related issues, docs, or commits>
```

### Commit Types

- **Add:** New feature, package, or module
- **Update:** Changes to existing functionality
- **Fix:** Bug fixes or corrections
- **Refactor:** Code restructuring without behavior change
- **Remove:** Deletion of features, packages, or code
- **Document:** Documentation-only changes
- **Style:** Formatting, whitespace (rare due to pre-commit hooks)

### Examples

**Good:**
```
Add battery monitoring service with event-driven alerts

Implement battery-monitor.sh using upower --monitor-detail for
event-driven notifications at 5%, 20%, and 100% battery levels.
This replaces polling approach for better efficiency.

Service defined in home-manager/battery-notifications/default.nix
Script uses pkgs.writeShellScript pattern with dependency injection.
```

**Good:**
```
Fix Ironbar volume module crash with PulseAudio

Replace built-in volume module with custom wpctl-based script.
The built-in module causes crashes when PulseAudio is active.

Workaround documented in Common Gotchas section of CLAUDE.md.
Script located at home-manager/ironbar/modules/volume/
```

**Too vague:**
```
Update config
```

**Too brief (missing context):**
```
Add battery service
```

### When to Commit

- After each logical change that builds successfully
- Before and after major refactoring
- When documentation is updated alongside code
- When a feature is complete and tested

### Multi-file Commits

**Good:** Related changes in a single commit
```
Add fingerprint authentication for screen lock

- Configure PAM rules in modules/hardware/fprintd/default.nix
- Update swaylock PAM service with fprintd support
- Document timeout and retry settings
- Update README.md with fingerprint auth details
```

**Bad:** Unrelated changes in one commit
```
Add package X, fix bug Y, update README for Z
```

## Pre-commit Hooks

### Installed Hooks

Configured via `flake.nix` and managed by `pre-commit-hooks.nix`:

**nixfmt:**
- Formats all `.nix` files
- Runs automatically on `git commit`
- Can also run manually: `nix fmt`

### Running Hooks Manually

```bash
# Format all files
nix fmt
# or (when in devenv environment)
nixfmt **/*.nix

# Format specific files
nixfmt file.nix

# Check without changing
nix fmt -- --check .
```

### Pre-commit Hook Workflow

1. **On `git commit`:**
   - Hook runs automatically
   - Formats staged `.nix` files
   - Updates staged files with formatting
   - Commit proceeds with formatted files

2. **If formatting changes files:**
   - Review the changes: `git diff`
   - If good, files are already staged
   - Commit completes normally

### Bypassing Hooks

**Not recommended,** but if necessary:

```bash
# Skip hooks (only for emergencies)
git commit --no-verify -m "message"
```

**When you might need this:**
- Emergency fix needed immediately
- Hook is broken (fix hook first!)
- Never for normal development

### Adding New Hooks

In `flake.nix`, add to pre-commit-hooks:

```nix
hooks = {
  nixfmt.enable = true;
  # Add new hook:
  new-hook = {
    enable = true;
    entry = "${pkgs.tool}/bin/tool args";
    files = "\\.(nix|sh)$";
  };
};
```

### Troubleshooting Hooks

**Hook fails on commit:**
1. Read error message
2. Fix the file manually
3. Stage the fix
4. Commit again

**Hook not running:**
1. Ensure direnv is active: `direnv allow`
2. Re-enter directory to reload
3. Check `.git/hooks/pre-commit` exists

## Documentation Practices

### Always Keep Documentation Updated

**Critical Rule:** README.md must always be current with the latest system state.

When making changes, update documentation in this order:
1. **README.md** - Update if user-facing features, packages, or workflows change
2. **Relevant docs/** - Update existing documentation that covers the changed area
3. **Create new docs/** - Document complex changes, quirks, or workarounds

### When to Create Documentation

Create a new file in `docs/` when:
- **Complex changes:** Multi-step processes that future developers need to understand
- **Quirks and workarounds:** Non-obvious solutions to specific problems
- **System integration:** How different components work together (e.g., ironbar-niri-overview.md)
- **Setup procedures:** Multi-step configuration that needs to be reproducible

### When to Update Existing Documentation

Update existing docs when:
- **Package lists change:** Update README.md software sections
- **Workflow changes:** Update development commands or processes
- **Configuration patterns change:** Update relevant docs/ files
- **Features are added/removed:** Update README.md and related docs/
- **Known issues are fixed:** Remove from gotchas, add to docs/ if solution is complex

### Documentation Structure

**README.md** - User-facing documentation:
- Quick start commands
- Installed software and features
- Keyboard shortcuts
- Hardware information
- References to detailed guides in docs/

**docs/** - Detailed technical guides:
- `structure.md` - Repository organization
- `adding-packages.md` - Package management
- `new-host.md` - Adding machines
- `secure-boot.md` - Secure boot setup
- `fingerprint-setup.md` - Fingerprint authentication
- `stylix-darkman-setup.md` - Theming deep dive
- `ironbar-niri-overview.md` - Status bar integration

**CLAUDE.md** - AI agent guidelines (this file):
- Development workflow
- Configuration patterns
- Code style
- Common gotchas

### Example Documentation Scenarios

**Scenario 1: Adding a new package**
- Add to appropriate packages.nix file
- Run `rebuild switch`
- Update README.md software list
- If complex setup needed, create docs/package-name-setup.md

**Scenario 2: Fixing a quirk**
- Implement the fix
- Document the quirk and solution in docs/
- Add to Common Gotchas in CLAUDE.md if relevant for future development
- Update README.md if it affects user workflow

**Scenario 3: Changing keyboard shortcuts**
- Update niri/binds.nix
- Update README.md keyboard shortcuts table
- Run `rebuild switch`

**Scenario 4: Complex system integration**
- Implement the integration
- Create docs/integration-name.md explaining how it works
- Add reference to README.md
- Add patterns to CLAUDE.md if it establishes new conventions

### Documentation Best Practices

- **Be specific:** Include file paths, line numbers, and exact commands
- **Explain why:** Document the reasoning behind non-obvious decisions
- **Keep it current:** Remove outdated information immediately
- **Cross-reference:** Link related documentation
- **Test commands:** Verify all commands in documentation actually work