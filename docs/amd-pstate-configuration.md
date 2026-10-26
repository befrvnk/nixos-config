# AMD P-State CPU Frequency Scaling Configuration

## Overview

This document explains the AMD P-State configuration used in this NixOS setup, including what Energy Performance Preference (EPP) is, how Active mode works with the scx_lavd scheduler, and the power management architecture.

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

## Current Configuration: Active Mode + scx_lavd

After initially switching to Passive mode to work around BIOS EPP limitations, we returned to **Active mode** so the CPU hardware handles frequency autonomously via EPP, while the `scx_lavd` sched_ext scheduler handles task placement and core gating on top of it.

### Why Active Mode Now?

Active mode (`amd_pstate=active`) exposes EPP via sysfs and lets the CPU hardware make low-latency autonomous frequency decisions. This pairs well with the `scx_lavd` scheduler, which focuses on task placement and responsiveness rather than frequency control.

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
- **On battery / Balanced**: Switches to `framework-battery` (low-power, EPP=power, boost OFF, WiFi power save ON, ABM 3)
- **On AC / Balanced**: Switches to `framework-ac` (balanced, EPP=balance_performance, boost ON, WiFi power save OFF, ABM off)
- **Power Saver**: `framework-powersave` (low-power, EPP=power, boost OFF, WiFi power save ON, ABM 4)
- **Performance**: `framework-performance` (performance, EPP=performance, boost ON, WiFi power save OFF, ABM off)

This approach has minimal CPU overhead (event-based via upower, not polling or per-second udev events).

Additional udev rules:
- **USB autosuspend**: Enabled for all devices except HID (keyboard/mouse)

Use Noctalia’s power-profile control to switch manually; it drives tuned-ppd over D-Bus.

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

## How Active Mode + scx_lavd Work Together

### The Power Management Stack

```
┌─────────────────────────────────────────────────────────────┐
│              tuned + tuned-ppd                               │
│         Custom: framework-battery / ac / powersave / perf    │
│         PPD API: power-saver / balanced / performance        │
│         Controls: platform profile + EPP + WiFi + ABM        │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│              scx_lavd scheduler                             │
│    Latency virtual deadlines, core compaction               │
│    Power mode follows system load (--autopilot)             │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│           AMD P-State Active (EPP)                           │
│         Hardware-controlled frequency scaling                │
│         Uses EPP hints for power/performance balance         │
└─────────────────────────────────────────────────────────────┘
```

### Benefits of This Architecture

1. **Responsiveness under load**: lavd's latency-criticality virtual deadlines keep latency-sensitive tasks responsive even when all cores are saturated by parallel builds
2. **Core compaction by load**: `--autopilot` consolidates work onto fewer cores and parks the rest when the machine is idle, releasing them again as load rises
3. **Hardware Efficiency**: Active mode lets the CPU make autonomous frequency decisions with lower latency
4. **Layered Control**: Platform profile controls system-wide behavior, while scx_lavd optimizes task scheduling

### Trade-offs

| Aspect | Active Mode + scx_lavd | Previous Passive Mode |
|--------|------------------------|----------------------|
| Frequency control | Hardware autonomous | Kernel controlled |
| Scheduling | scx_lavd (userspace BPF) | CFS (kernel) |
| Power optimization | Core compaction (load-based) | schedutil governor |
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

### Tuning scx_lavd
If the default behavior doesn't suit your workload, adjust the options in `modules/services/scx.nix`:
```nix
# Follow the tuned power profile instead of the system load
# (battery-first, but stays in powersave while a build runs)
extraArgs = [ "--autopower" ];

# Pin a mode instead of adapting: "--performance" | "--balanced" | "--powersave"
extraArgs = [ "--performance" ];

# Longer scheduling slices for throughput-oriented workloads (default 5000us)
extraArgs = [ "--slice-max-us" "10000" ];
```

### Switching Back to Passive Mode
If EPP-based scheduling causes issues, you can return to kernel-controlled frequency scaling:
```nix
boot.kernelParams = [ "amd_pstate=passive" ];
```
This enables full governor support (`schedutil`, `ondemand`, etc.). lavd has no frequency
driver control either way, so frequency stays with the governor/EPP.

### Alternative Schedulers
If scx_lavd doesn't work well for your use case:
- `scx_flash` - EDF with dynamic latency weighting and profile-gated core domains (the scheduler used here before lavd)
- `scx_bpfland` - vruntime scheduler that explicitly prioritizes interactive tasks
- `scx_rusty` - Better for throughput-focused workloads
- `scx_simple` - Minimal reference scheduler

## Unified Power Profiles

This system uses **unified power profiles** via tuned that control multiple power settings with a single toggle. Custom tuned profiles (`framework-battery`, `framework-ac`, `framework-powersave`, `framework-performance`) provide Framework-specific optimizations.

### Available Profiles

| PPD Profile | tuned Profile | Platform | EPP | Boost | ABM |
|-------------|---------------|----------|-----|-------|-----|
| 🔋 **Power Saver** | `framework-powersave` | `low-power` | `power` | Off | 4 |
| ⚡ **Balanced (battery)** | `framework-battery` | `low-power` | `power` | Off | 3 |
| ⚡ **Balanced (AC)** | `framework-ac` | `balanced` | `balance_performance` | On | 0 |
| 🚀 **Performance** | `framework-performance` | `performance` | `performance` | On | 0 |

`framework-powersave` and `framework-performance` use sysfs scripts because tuned’s
`[cpu] boost` setting does not work on this host.

### How to Switch Profiles

**Via Noctalia (Recommended):**
1. Open the control center or power-profile shortcut
2. Select Power Saver, Balanced, or Performance

**Via Command Line:**
```bash
# Check the active tuned profile
tuned-adm active

# List tuned profiles
tuned-adm list

# Switch directly (Noctalia/tuned-ppd normally handles this)
tuned-adm profile framework-performance
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
| **AC / Balanced** | framework-ac | balanced | Good performance with efficiency |
| **Battery / Balanced** | framework-battery | balanced | Maximize battery life |
| **Power Saver** | framework-powersave | power-saver | Explicit maximum savings |
| **Performance** | framework-performance | performance | Full boost and throughput |

To use **Performance** mode (for compilation, heavy work), manually select it in Noctalia.

### Implementation Details

**Files:**
- `modules/hardware/power-management.nix` - tuned configuration with custom profiles
- `home-manager/nixos/noctalia/default.nix` - Current shell integration

**Power settings managed:**
| Setting | Power Saver | Balanced (battery) | Balanced (AC) | Performance | Method |
|---------|-------------|-------------------|---------------|-------------|--------|
| Platform profile | low-power | low-power | balanced | performance | tuned `[acpi]` |
| EPP | power | power | balance_performance | performance | tuned `[cpu]` |
| CPU boost | Off | Off | On | On | tuned `[script]` |
| WiFi power save | On | On | Off | Off | tuned `[script]` |
| ABM (panel power savings) | 4 | 3 | 0 | 0 | tuned `[script]` |
| USB autosuspend | Auto (except HID) | Auto (except HID) | Auto (except HID) | Auto (except HID) | udev rules |
| Audio power save | Disabled | Disabled | Disabled | Disabled | modprobe config |

**Why audio power save is disabled:**
Enabling `snd_hda_intel power_save=1` causes pipewire/wireplumber to repeatedly handle codec wake/sleep cycles, generating excessive DBUS traffic (~300 msg/sec vs ~70 msg/sec) and CPU overhead. The ~0.1-0.3W savings is offset by increased CPU usage.

No sudo required for profile switching - tuned-ppd uses D-Bus for authorization.

## SCX sched_ext Scheduler

This system uses the **SCX (sched_ext)** BPF scheduler framework with **scx_lavd** for responsive, latency-aware scheduling.

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
    scheduler = "scx_lavd";
    extraArgs = [ "--autopilot" ];
  };
}
```

### Why scx_lavd?

**scx_lavd** (Latency-criticality Aware Virtual Deadline) derives each task's virtual
deadline from how latency-critical it has already proven to be:

- **Latency-criticality aware**: Tasks that release the CPU early (frequent short bursts, e.g. UI, input, audio) get tighter deadlines and are prioritized over tasks that fully consume their time slice (e.g. compilers)
- **Responsive under overcommit**: Designed to stay responsive and consistent even when all cores are saturated by CPU-bound builds
- **`--autopilot`**: Picks the power mode from *system load* - performance while a build runs (interactive work stays responsive without switching the tuned profile), powersave at idle
- **Core compaction**: In powersave/balanced modes work consolidates onto fewer cores so the others can sleep, which is the "park unused cores" battery behaviour
- **No cpufreq control**: On this host frequency is handled by `amd_pstate=active` EPP (hardware autonomous), not schedutil

### Alternative Schedulers

- `scx_bpfland` - vruntime scheduler that explicitly prioritizes interactive tasks (lavd/rustland lineage)
- `scx_rusty` - Work-conserving scheduler (good for throughput)
- `scx_simple` - Minimal reference scheduler

### How scx_lavd + AMD P-State Work Together

```
AMD P-State (Active)     →  Controls CPU frequency (hardware autonomous)
         ↓
scx_lavd                 →  Task placement + core compaction under light load
         ↓
Virtual deadlines        →  Interactive tasks stay responsive under load
```

Together they provide:
- Responsiveness even under saturated CPU-bound workloads (parallel builds)
- Efficient core utilization (idle cores sleep deeply on battery)
- Low-latency scheduling for interactive tasks
- Hardware-controlled frequency scaling

### Verification

```bash
# Check if scx_lavd is running
systemctl status scx

# Check the active scheduler via sysfs (no root needed)
cat /sys/kernel/sched_ext/state      # enabled
cat /sys/kernel/sched_ext/root/ops   # lavd_1.1.4_x86_64_unknown_linux_gnu

# ...or straight from the kernel log
journalctl -k -b -g 'sched_ext: BPF scheduler' | tail -1
# sched_ext: BPF scheduler "lavd_1.1.4_x86_64_unknown_linux_gnu" enabled

# Event counters (no root) and full stats (root only)
cat /sys/kernel/sched_ext/root/events
sudo ls /sys/kernel/debug/sched_ext/
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

tuned-ppd provides PPD API compatibility for clients such as Noctalia. Install
`power-profiles-daemon` if you also want the `powerprofilesctl` CLI.

### Noctalia V5 Integration

Noctalia's built-in power controls use the power-profiles API exposed by tuned-ppd.
The profile mappings and automatic AC/battery behavior remain configured in
`modules/hardware/power-management.nix`; do not enable a competing power daemon.

**Implementation files:**
- `home-manager/nixos/noctalia/default.nix` - Shell configuration
- `modules/hardware/power-management.nix` - tuned profiles and PPD mappings

The legacy Ironbar/Quickshell profile helpers were removed; Noctalia owns the
power-profile controls.

### Manual Switching

```bash
# Check active profile
tuned-adm active

# List profiles
tuned-adm list

# Switch directly (Noctalia/tuned-ppd normally handles this)
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
  - tuned enablement with custom profiles (framework-battery, framework-ac, framework-powersave, framework-performance)
  - tuned-ppd for PPD API compatibility
  - Audio power save config (disabled)
  - Kernel parameters (nmi_watchdog, ASPM, amd_pstate)
  - udev rules (USB autosuspend, I/O scheduler)
- `modules/services/scx.nix` - SCX sched_ext scheduler configuration
- `home-manager/nixos/noctalia/` - Active desktop shell integration

---

**Last Updated**: 2026-10-23
**Applies To**: Framework Laptop 13 (AMD Ryzen AI 300 Series), NixOS 26.11
