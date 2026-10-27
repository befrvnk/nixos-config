# NixOS System Modules

This directory contains NixOS-only system-level configuration. Darwin does NOT use these modules.

## Organization

```
modules/
├── default.nix        # Central import file - each NixOS host imports this
├── users.nix          # User account definitions
├── desktop/           # Display manager (greetd), compositor
├── hardware/          # fprintd, power management, keyboard
├── services/          # System services (pipewire, bluetooth, scx, oomd)
├── system/            # Core settings (boot, networking, packages, security)
└── theming/           # System-level stylix config
```

## System vs Home-Manager Split

**System Level (here):** Root-level, affects all users
- Boot configuration (LUKS, TPM2, secure boot via Lanzaboote)
- Hardware drivers and firmware
- System services (greetd, pipewire); runtime theme control is in Home Manager Noctalia
- Network management, power management
- Security (PAM, polkit, TPM, firewall)
- System users and groups

**Home-Manager Level:** User-specific (see `home-manager/AGENTS.md`)

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

### Noctalia Greeter
- `desktop/greetd.nix` enables the pinned nixpkgs Noctalia Greeter module, replacing
  tuigreet only; greetd remains the daemon and Niri remains the selected session.
- Password-entry default is explicit (allow_empty_password=false). Frontend gating
  alone didn't consume the password: the initial inherited fingerprint login left
  the keyring locked. While Noctalia Greeter is enabled, only greetd auth is forced
  to required pam_unix (no nullok/permit) then optional pam_gnome_keyring. Drop both
  inherited login auth and direct greetd fingerprint rules; keep account/password/
  session includes and all other PAM/fprintd/lid routes unchanged. Never cache
  credentials in files or disable keyring encryption to avoid a prompt.
- Its short environment wrapper scopes NixOS session-data/PATH and patched custom
  XKB root/model to the greeter. Do not set a global greeter-only environment or
  assume /run/current-system/sw/share/wayland-sessions contains Niri.
- Greeter.toml is store-backed; sync.toml remains mutable. Passwordless sync users
  stay empty; do not add a broad Polkit bypass or run the privileged helper as agent.
- `checks.x86_64-linux.noctalia-greeter` tests private wrapper fixtures, real session
  listing, device-free XKB probe, exact greetd password/keyring auth and all other
  PAM invariance (8 probes). Never run the real greeter/compositor or authenticate.
  UI/Niri and corrected single-password/keyring startup passed after user reboot
  on 2026-10-23: required password auth, cached token, keyring unlocked in session.
  Don't mistake the earlier missing-control-file/stash log for a failure when
  followed by successful session unlock. Appearance sync/negative-password UI and
  multi-output coverage are not implied by that successful login.
- Stage this trial via user boot/reboot, not service restart; native greetd's
  restartIfChanged=false remains. Keep previous generation and TTY/password recovery.
  See docs/noctalia-desktop-roadmap.md; Umbriel/topbar are separate later steps.

### Umbriel trial
- Framework explicitly imports desktop/umbriel.nix; nixpkgs supplies the native
  NixOS module, while `lib/overlays.nix` overlays the compositor and its portal
  from the `umbriel` flake input (`github:noctalia-dev/umbriel/cachix`). Both move
  together; umbriel.cachix.org is trusted in `shared/caches.nix`/`flake.nix`.
  Never set `inputs.umbriel.inputs.nixpkgs.follows` or the cache paths miss.
- Niri stays installed/default. Only the entry launcher is wrapped: load the
  declarative per-user HM environment for Nushell, set patched XKB before config
  validation, stop a stale graphical-session.target left by a previous logout
  (logind only removes the session scope; user units survive), then exec native
  start-umbriel. Keep the native session/unit lifecycle.
- Standard HM profile exports tolerate unset optional variables; don't source them
  under set -u. The fixture check exercises the actual generated profile too.
- Candidate config/bar/PAM/idle/logind/Niri invariance and offline CLI/render/launcher
  checks live in checks.x86_64-linux.umbriel-trial. Never launch a compositor,
  display, portal, hardware, lock, suspend or authentication probe as an agent.
- The upstream unit is Type=notify and its binary provides matching readiness;
  nixpkgs' module keeps restartIfChanged=false/enableDefaultPath=false. Live
  portal/session behavior is still pending.
- Owner chose to retain both Niri and Umbriel (2026-10-23), with Niri default.
  Performance comparisons are user-led backlog NOC-04, not mandatory next tests.
  Do not uninstall either or change the default without a new request. Native
  Alt+Tab is installed/user-confirmed with valid reload and no compositor restart;
  don't turn that into full runtime/performance or unreported-case acceptance.
- See docs/umbriel-trial.md for differences and user-only trial/recovery. No Niri,
  fallback/auth removal or topbar redesign is authorized by installing a second WM.

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

### Native Noctalia lock authentication
- `services/noctalia-auth.nix` adds a dedicated password-only pam_unix stack.
- Pinned V5 hardcodes login; the exact-context home-manager package patch selects
  noctalia instead. Don't change login/TTY/sudo/polkit/swaylock PAM to fit the client.
- Fingerprints are native fprintd D-Bus, not this password stack. Password PAM and
  manual native password/fingerprint passed. Automatic cutover is prepared with
  native sleep-delay and guarded idle suspend; do not claim live sleep/resume proof
  from configuration tests. Retain fallback PAM until user acceptance.
- Agents never authenticate, scan fingerprints, lock or suspend the real session.
  See `docs/noctalia-lockscreen-migration.md` for manual validation/recovery boundaries.

## Power Management

### tuned + tuned-ppd
In `modules/hardware/power-management.nix`:
- **tuned** manages power profiles with **tuned-ppd** providing PPD API compatibility
- PPD clients use the tuned-ppd D-Bus API; `powerprofilesctl` is not installed by default
- **Auto-switching:** tuned handles AC/battery via upower events (not udev)
- Custom profiles: `framework-battery`, `framework-ac`, `framework-powersave`, `framework-performance`

**Power Saver:** low-power profile, EPP=power, boost OFF, WiFi power save ON, ABM level 4
**Battery/Balanced:** low-power profile, EPP=power, boost OFF, WiFi power save ON, ABM level 3
**AC/Balanced:** balanced profile, EPP=balance_performance, boost ON, WiFi power save OFF, ABM disabled
**Performance:** performance profile, EPP=performance, boost ON, WiFi power save OFF, ABM disabled

`framework-powersave` and `framework-performance` run sysfs scripts because tuned's
`[cpu] boost` setting does not work on this host.

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
- Level 4: Maximum (explicit Power Saver)
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
- Uses `scx_lavd` BPF scheduler (Latency-criticality Aware Virtual Deadline)
- `--autopower` takes the power mode from the tuned/PPD profile: powersave with core
  compaction on battery profiles, balanced on AC. The bar's profile switch controls it;
  system load does not override it.
- No cpufreq control: frequency is left to `amd_pstate=active` EPP (hardware autonomous)
- `flash`'s flags (`--primary-domain`, `--throttle-us`) are *not* valid for lavd - the
  service fails to start with `unexpected argument`
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
