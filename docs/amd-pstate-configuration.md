# AMD P-State CPU Frequency Scaling Configuration

## Overview

This document explains the AMD P-State configuration used in this NixOS setup, including what Energy Performance Preference (EPP) is, how Active mode works with the scx_flash scheduler, and the power management architecture.

## What is AMD P-State?

AMD P-State is a CPU frequency scaling driver for modern AMD processors that provides better power management and performance than the older `acpi-cpufreq` driver. It has three operating modes:

### 1. **Active Mode** (`amd-pstate-epp`)
- Uses Energy Performance Preference (EPP) for autonomous CPU frequency control
- The **CPU hardware** makes frequency decisions independently
- The OS provides only "hints" about performance vs efficiency preferences
- Limited to two pseudo-governors: `performance` and `powersave`
- More efficient on systems with proper BIOS/firmware support

### 2. **Passive Mode** (`amd-pstate`)
- Uses traditional kernel-based frequency scaling
- The **Linux kernel** controls frequency decisions based on workload
- Supports full range of governors: `schedutil`, `ondemand`, `conservative`, `performance`, `powersave`
- Better integration with Linux scheduler
- More predictable behavior across different hardware

### 3. **Guided Mode** (`amd-pstate-guided`)
- Hybrid approach between Active and Passive
- Kernel provides guidance but CPU has final say
- Similar governor support to Passive mode

## What is EPP (Energy Performance Preference)?

**EPP** is a hardware feature that allows the operating system to tell the CPU how to balance performance vs power consumption when the CPU itself is making autonomous frequency scaling decisions.

### How EPP Works

In traditional frequency scaling (Passive mode):
```
Workload → Linux Scheduler → Governor (schedutil) → CPU Frequency Change
```

In EPP-based scaling (Active mode):
```
Workload → CPU's Internal Controller (uses EPP hint) → CPU Frequency Change
                ↑
         OS provides EPP preference
```

### EPP Values

When using Active mode, these preferences are available:
- `performance` - Prioritize speed, run at higher frequencies
- `balance_performance` - Balanced with slight performance bias
- `default` - Hardware default behavior
- `balance_power` - Balanced with slight efficiency bias
- `power` - Prioritize power savings, run at lower frequencies

**Note**: Not all CPUs/BIOS expose all EPP values. Some systems may only expose `performance`.

## Problem We Encountered

### Initial Configuration
The system was using AMD P-State Active mode with the following behavior:
- **Driver**: `amd-pstate-epp` (Active mode)
- **Available governors**: `performance`, `powersave` (pseudo-governors only)
- **Available EPP preferences**: `performance` only (BIOS limitation)
- **TLP configuration**: Attempted to use `CPU_SCALING_GOVERNOR_ON_AC = "performance"`

### Issue
With the CPU locked to `performance` EPP and no ability to use `schedutil` or other advanced governors:
- Niri compositor showed high idle CPU usage
- **Baseline measurements**:
  - Average CPU: 4.63%
  - Peak CPU: up to 16.8%
- CPU was not efficiently scaling down during idle periods
- The `performance` EPP kept CPU frequencies high even when unnecessary

### Why EPP Was Limited
On the Framework AMD Ryzen AI 300 series with current BIOS (03.04):
- Only `performance` EPP preference was exposed by hardware
- This is likely a BIOS/firmware limitation or early hardware support issue
- Without `balance_performance` or `power` EPP options, Active mode couldn't dynamically adjust behavior

## Current Configuration: Active Mode + scx_flash

After initially switching to Passive mode to work around BIOS EPP limitations, we returned to **Active mode** so the CPU hardware handles frequency autonomously via EPP, while the `scx_flash` sched_ext scheduler handles task placement and core gating on top of it.

### Why Active Mode Now?

Active mode (`amd_pstate=active`) exposes EPP via sysfs and lets the CPU hardware make low-latency autonomous frequency decisions. This pairs well with the `scx_flash` scheduler, which focuses on task placement and responsiveness rather than frequency control.

### Kernel Parameter
Configured in `modules/hardware/power-management.nix`:
```nix
boot.kernelParams = [
  "nmi_watchdog=0"
]
++ lib.optionals isAmd [ "amd_pstate=active" ];
```

This uses the `amd-pstate-epp` driver (Active mode) for hardware-controlled frequency scaling.

### tuned with PPD Compatibility
Power management uses **tuned** (Red Hat's power management daemon) with **tuned-ppd** for PPD API compatibility:
```nix
# In modules/hardware/power-management.nix
services.tuned = {
  enable = true;
  ppdSupport = true;  # Enables tuned-ppd for PPD API compatibility
};
```

tuned provides event-based AC/battery switching via upower, eliminating the CPU overhead of udev rules that fire on every battery status update.

### Automatic AC/Battery Switching
tuned-ppd handles automatic profile switching via upower events (not udev):
- **On battery**: Switches to `framework-battery` profile (low-power platform profile, EPP=power, boost OFF, WiFi power save ON, ABM level 3)
- **On AC**: Switches to `framework-ac` profile (balanced platform profile, EPP=balance_performance, boost ON, WiFi power save OFF, ABM disabled)

This approach has minimal CPU overhead (event-based via upower, not polling or per-second udev events).

Additional udev rules:
- **USB autosuspend**: Enabled for all devices except HID (keyboard/mouse)

Use the Ironbar battery popup to manually switch to "performance" when needed.

## Verification

### Check Current Configuration
```bash
# Verify Active mode is in use
$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
amd-pstate-epp  # ✅ Active mode

# Check EPP is available
$ cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference
balance_performance  # or performance, power, etc.

# List available EPP values
$ cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_available_preferences
```

## How Active Mode + scx_flash Work Together

### The Power Management Stack

```
┌─────────────────────────────────────────────────────────────┐
│              tuned + tuned-ppd                               │
│         Custom profiles: framework-battery / framework-ac    │
│         PPD API: power-saver / balanced / performance        │
│         Controls: platform profile + EPP + WiFi + ABM        │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│              scx_flash scheduler                            │
│    EDF + latency weighting, core gating                     │
│    Primary domain follows the power profile                 │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│           AMD P-State Active (EPP)                           │
│         Hardware-controlled frequency scaling                │
│         Uses EPP hints for power/performance balance         │
└─────────────────────────────────────────────────────────────┘
```

### Benefits of This Architecture

1. **Responsiveness under load**: flash's EDF + dynamic latency weighting keeps latency-sensitive tasks responsive even when all cores are saturated by parallel builds
2. **Core gating by power profile**: `--primary-domain auto` prioritizes the efficient cores and parks unused ones when on battery
3. **Hardware Efficiency**: Active mode lets the CPU make autonomous frequency decisions with lower latency
4. **Layered Control**: Platform profile controls system-wide behavior, while scx_flash optimizes task scheduling

### Trade-offs

| Aspect | Active Mode + scx_flash | Previous Passive Mode |
|--------|------------------------|----------------------|
| Frequency control | Hardware autonomous | Kernel controlled |
| Scheduling | scx_flash (userspace BPF) | CFS (kernel) |
| Power optimization | Core gating + throttle | schedutil governor |
| EPP support required | No (frequency via hardware) | No |
| Latency | Lower (hardware decisions) | Slightly higher |

## Monitoring CPU Behavior

### Check Current Configuration
```bash
# Current driver
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver

# Active governor
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Current CPU frequency
watch -n 1 grep MHz /proc/cpuinfo
```

### Monitor Frequency Scaling
```bash
# Watch CPU frequencies in real-time
watch -n 0.5 'grep MHz /proc/cpuinfo | head -8'
```

You should see frequencies scale down to ~400-800 MHz during idle and scale up to 3000+ MHz under load.

## Future Considerations

### Tuning scx_flash
If the default behavior doesn't suit your workload, adjust the options in `modules/services/scx.nix`:
```nix
# More battery life (inject more idle cycles; 0 = off)
extraArgs = [ "--throttle-us" "400" ];

# Use all cores / fastest cores for heavy parallel builds
# instead of gating to the efficient cores
# "performance" or "all" are options; default is "auto"
extraArgs = [ "--primary-domain" "all" ];

# More responsive interactive tasks (bursty UI/audio)
extraArgs = [ "--slice-us-lag" "30000" ];
```

### Switching Back to Passive Mode
If EPP-based scheduling causes issues, you can return to kernel-controlled frequency scaling:
```nix
boot.kernelParams = [ "amd_pstate=passive" ];
```
This enables full governor support (`schedutil`, `ondemand`, etc.) and lets scx_flash optionally drive frequency via `--cpufreq`.

### Alternative Schedulers
If scx_flash doesn't work well for your use case:
- `scx_bpfland` - vruntime scheduler that explicitly prioritizes interactive tasks (lavd/rustland lineage)
- `scx_rusty` - Better for throughput-focused workloads
- `scx_simple` - Minimal reference scheduler

## Unified Power Profiles

This system uses **unified power profiles** via tuned that control multiple power settings with a single toggle. Custom tuned profiles (`framework-battery`, `framework-ac`) provide Framework-specific optimizations.

### Available Profiles

| Profile | Platform Profile | EPP | CPU Boost | Use Case |
|---------|------------------|-----|-----------|----------|
| 🔋 **Power Saver** | `low-power` | `power` | Off | Max battery life |
| ⚡ **Balanced** | `balanced` | `balance_performance` | On | Battery + dev work |
| 🚀 **Performance** | `performance` | `performance` | On | Full power on AC |

### How to Switch Profiles

**Via Battery Popup (Recommended):**
1. Click the battery icon in Ironbar
2. Select desired profile: low-power, balanced, or performance

**Via Command Line:**
```bash
# List available profiles (PPD API via tuned-ppd)
powerprofilesctl list

# Get current profile
powerprofilesctl get

# Set profile (no sudo needed)
powerprofilesctl set balanced

# Check active tuned profile
tuned-adm active
```

**What tuned Controls:**
- **Platform Profile**: Fans, thermals, and power limits (via `[acpi]` section)
- **EPP (Energy Performance Preference)**: CPU power/performance hints (via `[cpu]` section)
- **WiFi Power Save**: Network power management (via script plugin)
- **ABM (Adaptive Backlight)**: Display power savings (via script plugin)

### Automatic Switching

tuned-ppd automatically switches profiles based on battery status via upower:

| Power State | tuned Profile | PPD Profile | Why |
|-------------|---------------|-------------|-----|
| **AC (Charging)** | framework-ac | balanced | Good performance with efficiency |
| **Battery (Discharging)** | framework-battery | balanced→power-saver | Maximize battery life |

To use **Performance** mode (for compilation, heavy work), manually switch via the battery popup or `powerprofilesctl set performance`.

### Implementation Details

**Files:**
- `modules/hardware/power-management.nix` - tuned configuration with custom profiles
- `home-manager/ironbar/modules/battery/set-profile.sh` - Profile switcher (uses `tuned-adm`)
- `home-manager/ironbar/modules/battery/get-profile.sh` - Current profile reader (reads sysfs)

**Power settings managed:**
| Setting | Battery | AC | Method |
|---------|---------|-----|--------|
| Platform profile | low-power | balanced | tuned `[acpi]` section |
| EPP | power | balance_performance | tuned `[cpu]` section |
| CPU boost | Off | On | tuned `[cpu]` section |
| WiFi power save | On | Off | tuned `[script]` plugin |
| ABM (panel power savings) | Level 3 | Disabled | tuned `[script]` plugin |
| USB autosuspend | Auto (except HID) | Auto (except HID) | udev rules |
| Audio power save | Disabled | Disabled | modprobe config |

**Why audio power save is disabled:**
Enabling `snd_hda_intel power_save=1` causes pipewire/wireplumber to repeatedly handle codec wake/sleep cycles, generating excessive DBUS traffic (~300 msg/sec vs ~70 msg/sec) and CPU overhead. The ~0.1-0.3W savings is offset by increased CPU usage.

No sudo required for profile switching - tuned-ppd uses D-Bus for authorization.

## SCX sched_ext Scheduler

This system uses the **SCX (sched_ext)** BPF scheduler framework with **scx_flash** for responsive, latency-aware scheduling.

### What is sched_ext?

**sched_ext** is a Linux kernel feature that enables user-space schedulers written in BPF. This allows for:
- Custom scheduling policies without kernel modifications
- Easy experimentation with scheduling algorithms
- Workload-specific optimizations (gaming, power saving, etc.)

### Current Configuration

Configured in `modules/services/scx.nix`:

```nix
{
  services.scx = {
    enable = true;
    scheduler = "scx_flash";
    extraArgs = [ "--primary-domain" "auto" "--throttle-us" "200" ];
  };
}
```

### Why scx_flash?

**scx_flash** (Intel's live scheduler) uses an **earliest deadline first (EDF)** policy with dynamic latency weighting:

- **Dynamic latency weight**: Tasks that release the CPU early (frequent short bursts, e.g. UI, input, audio) get a higher latency weight and are prioritized over tasks that fully consume their time slice (e.g. compilers)
- **Responsive under overcommit**: Designed to stay responsive and consistent even when all cores are saturated by CPU-bound builds
- **`--primary-domain auto`**: Gates the initial dispatch domain based on the active power profile, preferring efficient cores on battery and parking unused ones
- **`--throttle-us`**: Periodically injects idle cycles to extend battery life and reduce heat/fan noise
- **No `--cpufreq`**: On this host frequency is handled by `amd_pstate=active` EPP (hardware autonomous), not schedutil

### Alternative Schedulers

- `scx_bpfland` - vruntime scheduler that explicitly prioritizes interactive tasks (lavd/rustland lineage)
- `scx_rusty` - Work-conserving scheduler (good for throughput)
- `scx_simple` - Minimal reference scheduler

### How scx_flash + AMD P-State Work Together

```
AMD P-State (Active)     →  Controls CPU frequency (hardware autonomous)
         ↓
scx_flash                →  Task placement + core gating by power profile
         ↓
Latency weighting        →  Interactive tasks stay responsive under load
```

Together they provide:
- Responsiveness even under saturated CPU-bound workloads (parallel builds)
- Efficient core utilization (idle cores sleep deeply on battery)
- Low-latency scheduling for interactive tasks
- Hardware-controlled frequency scaling

### Verification

```bash
# Check if scx_flash is running
systemctl status scx

# Check scheduler via sysfs
cat /sys/kernel/sched_ext/root/type
# Should show: flash

# View scheduler statistics
cat /sys/kernel/sched_ext/root/stats/*
```

### Troubleshooting

If the system feels sluggish:
1. Check SCX service: `systemctl status scx`
2. Restart SCX: `sudo systemctl restart scx`
3. Verify EPP is available: `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference`
4. Try a different scheduler or mode by editing `modules/services/scx.nix`

## Platform Profile Switching

Modern AMD laptops support **ACPI platform profiles** for system-wide power/performance settings. This is managed by **tuned** with **tuned-ppd** providing PPD API compatibility.

### Available Profiles

| Profile | Description | Use Case |
|---------|-------------|----------|
| `power-saver` | Maximum battery life | Light tasks, reading |
| `balanced` | Default behavior | Normal usage |
| `performance` | Maximum performance | Heavy workloads |

### How It Works

tuned manages power settings via custom profiles:
- Platform profile (fans, TDP, power limits) via `[acpi]` section
- Energy Performance Preference (EPP) via `[cpu]` section
- WiFi power save and ABM via `[script]` plugin

tuned-ppd provides PPD API compatibility so `powerprofilesctl` commands work.

### Ironbar Integration

The battery popup in Ironbar includes power profile switching:
- Click the battery icon in the status bar
- Select desired profile in the popup
- Profile changes immediately via `tuned-adm` (applies all settings: EPP, boost, WiFi, ABM)

**Implementation files:**
- `home-manager/ironbar/modules/battery/get-profile.sh` - Reads current profile from sysfs
- `home-manager/ironbar/modules/battery/set-profile.sh` - Sets profile via `tuned-adm`

### Manual Switching

```bash
# Via PPD API (tuned-ppd)
powerprofilesctl get
powerprofilesctl list
powerprofilesctl set balanced

# Via tuned directly
tuned-adm active
tuned-adm list
tuned-adm profile framework-ac
```

### Relationship to Other Power Settings

| Feature | Scope | What It Controls |
|---------|-------|------------------|
| **tuned** | System-wide | Platform profile + EPP + WiFi + ABM |
| **AMD P-State** | CPU frequency | Hardware-controlled scaling |
| **SCX Scheduler** | Task scheduling | Which tasks run when/where |

tuned coordinates these settings via custom profiles, with tuned-ppd providing the PPD API for compatibility with existing tools.

## References

- [Arch Linux Wiki: CPU Frequency Scaling](https://wiki.archlinux.org/title/CPU_frequency_scaling)
- [AMD P-State Driver Documentation](https://www.kernel.org/doc/html/latest/admin-guide/pm/amd-pstate.html)
- [Linux Kernel schedutil Governor](https://docs.kernel.org/scheduler/schedutil.html)
- [sched_ext Documentation](https://github.com/sched-ext/scx)
- [ACPI Platform Profile](https://www.kernel.org/doc/html/latest/userspace-api/sysfs-platform_profile.html)

## Related Files

- `modules/hardware/power-management.nix` - Main power management configuration:
  - tuned enablement with custom profiles (framework-battery, framework-ac)
  - tuned-ppd for PPD API compatibility
  - Audio power save config (disabled)
  - Kernel parameters (nmi_watchdog, ASPM, amd_pstate)
  - udev rules (USB autosuspend, I/O scheduler)
- `modules/services/scx.nix` - SCX sched_ext scheduler configuration
- `home-manager/ironbar/modules/battery/` - Power profile switching in status bar

---

**Last Updated**: 2026-01-01
**Applies To**: Framework Laptop 13 (AMD Ryzen AI 300 Series), NixOS 25.05
