# NixOS System Modules

This directory contains NixOS-only system-level configuration. Darwin does NOT use these modules.

## Organization

```
modules/
├── default.nix        # Central import file - each NixOS host imports this
├── users.nix          # User account definitions
├── desktop/           # Display manager (greetd), compositor
├── hardware/          # fprintd, power management, keyboard
├── services/          # System services (darkman, pipewire, bluetooth, scx, oomd)
├── system/            # Core settings (boot, networking, packages, security)
└── theming/           # System-level stylix config
```

## System vs Home-Manager Split

**System Level (here):** Root-level, affects all users
- Boot configuration (LUKS, TPM2, secure boot via Lanzaboote)
- Hardware drivers and firmware
- System services (greetd, darkman daemon, pipewire)
- Network management, power management
- Security (PAM, polkit, TPM, firewall)
- System users and groups

**Home-Manager Level:** User-specific (see `home-manager/CLAUDE.md`)

## Security Patterns

### PAM Configuration (Fingerprint Auth)
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

### Firewall
Configured in `modules/system/security.nix`:
- **Incoming:** Blocked by default
- **Outgoing:** Allowed
- **Localhost:** Always allowed (dev servers work without config)
- To open ports: add to `allowedTCPPorts` or `allowedUDPPorts`

### Kernel Security Hardening
In `modules/system/security.nix`:
- `kernel.dmesg_restrict = 1` - Kernel logs root-only
- `kernel.sysrq = 0` - Disable Magic SysRq key
- `kernel.yama.ptrace_scope = 1` - Restrict process debugging
- Network hardening: disable IP forwarding, ignore ICMP redirects, enable SYN cookies
- See `docs/security-hardening.md` for full details

## Power Management

### tuned + tuned-ppd
In `modules/hardware/power-management.nix`:
- **tuned** manages power profiles with **tuned-ppd** providing PPD API compatibility
- `powerprofilesctl` still works (talks to tuned-ppd D-Bus API)
- **Auto-switching:** tuned handles AC/battery via upower events (not udev)
- Custom profiles: `framework-battery` and `framework-ac`

**Battery mode:** low-power profile, EPP=power, boost OFF, WiFi power save ON, ABM level 3
**AC mode:** balanced profile, EPP=balance_performance, boost ON, WiFi power save OFF, ABM disabled

### Platform Profile Permissions
`platform-profile-permissions` service makes sysfs writable for user control:
```bash
cat /sys/firmware/acpi/platform_profile  # low-power, balanced, performance
echo "balanced" > /sys/firmware/acpi/platform_profile
tuned-adm active  # Check active tuned profile
```

### USB Autosuspend
- Enabled via udev rules (except HID devices to prevent input lag)
- Audio power save disabled (causes DBUS spam with pipewire)

### ABM (Adaptive Backlight Management)
AMD panel power savings:
```bash
cat /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings  # 0-4
echo 3 > /sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings
```
- Level 0: Disabled (accurate colors)
- Level 3: Aggressive (battery)
- Toggle: `Mod+Shift+B` runs `toggle-abm`

## Audio Configuration

### PipeWire (`modules/services/pipewire.nix`)
- **48kHz forced:** Eliminates pops from rate switching
- **Node suspension disabled:** `session.suspend-timeout-seconds=0`
- Large headroom (8192) and period-size (1024) for stable playback
- Quantum: 1024 (~21ms), min 512, max 2048
- `link.max-buffers=128` (default 16 causes crackling)
- See: https://bbs.archlinux.org/viewtopic.php?id=280654

### Audio Power Saving (snd_hda_intel)
- `power_save=0` disables low-power timeout
- `power_save_controller=N` disables controller (critical for pops)
- Must be set via systemd service (`audio-power-save-controller`), not kernel param
- tuned profiles must set `[audio] timeout=0`
- See: https://www.kernel.org/doc/html/latest/sound/designs/powersave.html

### ALSA Master Volume (Framework)
- Framework defaults Master to 77% (-15 dB)
- `alsa-mixer-init` service sets Master and PCM to 100% at boot
- Card 1: HD-Audio Generic_1 (speakers)
- Check: `amixer -c1 scontents | grep -A2 "Master\|PCM"`

## System Optimizations

### SCX Scheduler (`modules/services/scx.nix`)
- Uses `scx_lavd` BPF scheduler with `--autopower`
- Requires `amd_pstate=active` kernel parameter
- Core Compaction: active cores faster, idle cores sleep
- **CachyOS kernel** provides best integration

### CachyOS-Style Sysctls (`modules/system/core.nix`)
Based on [CachyOS Settings](https://github.com/CachyOS/CachyOS-Settings):
- `vm.swappiness = 180` - ZRAM optimized
- `vm.vfs_cache_pressure = 50` - Better file cache
- `vm.dirty_bytes/dirty_background_bytes` - 256MB/64MB thresholds
- `vm.page-cluster = 0` - Single-page swap for ZRAM/SSD
- `fs.file-max = 2097152` - High file handle limit
- `kernel.kptr_restrict = 2` - Security hardening
- `rcutree.enable_rcu_lazy=1` - 5-10% power savings at idle
- THP defer+madvise, I/O scheduler `none` for NVMe

### systemd-oomd (`modules/services/oomd.nix`)
- Proactive OOM before kernel killer
- Works with ZRAM: high swappiness fills ZRAM first
- 20-second pressure duration (Fedora default)
- Check: `systemctl status systemd-oomd`, `journalctl -u systemd-oomd`

## Adding System Packages

Add to `modules/system/packages.nix` (git, vim, wget, core tools).
User packages go in `home-manager/nixos/packages.nix`.
