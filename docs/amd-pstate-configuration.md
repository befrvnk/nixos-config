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

## Current Configuration: Active Mode with scx_lavd

After initially switching to Passive mode to work around BIOS EPP limitations, we've now returned to **Active mode** to enable the scx_lavd scheduler's autopower feature.

### Why Active Mode Now?

The scx_lavd scheduler's `--autopower` flag reads the system's Energy Performance Preference (EPP) to automatically adjust its scheduling behavior. This requires Active mode (`amd_pstate=active`) which exposes EPP via sysfs.

### Kernel Parameter
Configured in `modules/hardware/power-management.nix`:
```nix
boot.kernelParams = [
  "nmi_watchdog=0"
]
++ lib.optionals isAmd [ "amd_pstate=active" ];
```

This uses the `amd-pstate-epp` driver (Active mode) for hardware-controlled frequency scaling.

### TLP Configuration
TLP continues to manage platform profiles and other power settings in `modules/hardware/power-management.nix`:
```nix
services.tlp.settings = {
  # CPU scaling governor (used by both modes)
  CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
  CPU_SCALING_GOVERNOR_ON_BAT = "schedutil";

  # Platform profile (system-wide power/thermal behavior)
  PLATFORM_PROFILE_ON_AC = "balanced";
  PLATFORM_PROFILE_ON_BAT = "low-power";
};
```

**Note:** In Active mode, the governor setting affects behavior differently than in Passive mode - the hardware still makes autonomous frequency decisions, but the governor provides hints.

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
│                    Platform Profile                          │
│         (TLP: power-saver / balanced / performance)          │
│         Controls: fans, thermals, power limits               │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│              scx_lavd --autopower                            │
│         Reads EPP → adjusts scheduling behavior              │
│         Core Compaction: idles unused cores                  │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────────────────────────────────────┐
│           AMD P-State Active (EPP)                           │
│         Hardware-controlled frequency scaling                │
│         Uses EPP hints for power/performance balance         │
└─────────────────────────────────────────────────────────────┘
```

### Benefits of This Architecture

1. **Adaptive Scheduling**: scx_lavd reads EPP and automatically adjusts between powersave/balanced/performance modes
2. **Core Compaction**: When CPU usage < 50%, active cores run faster while idle cores enter deep sleep (C-States)
3. **Hardware Efficiency**: Active mode lets the CPU make autonomous frequency decisions with lower latency
4. **Layered Control**: Platform profile controls system-wide behavior, while scx_lavd optimizes task scheduling

### Trade-offs

| Aspect | Active Mode + scx_lavd | Previous Passive Mode |
|--------|------------------------|----------------------|
| Frequency control | Hardware autonomous | Kernel controlled |
| Scheduling | scx_lavd (userspace BPF) | CFS (kernel) |
| Power optimization | Autopower + Core Compaction | schedutil governor |
| EPP support required | Yes | No |
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

### Alternative scx_lavd Modes
If autopower doesn't suit your workload, you can try explicit modes:
```nix
# For maximum performance (gaming, compiling)
extraArgs = [ "--performance" ];

# For maximum battery life
extraArgs = [ "--powersave" ];
```

### Switching Back to Passive Mode
If EPP-based scheduling causes issues, you can return to kernel-controlled frequency scaling:
```nix
boot.kernelParams = [ "amd_pstate=passive" ];
```
This enables full governor support (`schedutil`, `ondemand`, etc.) but loses scx_lavd's autopower feature.

### Alternative Schedulers
If scx_lavd doesn't work well for your use case:
- `scx_rusty` - Better for throughput-focused workloads
- `scx_bpfland` - General-purpose with tunable parameters

## Dynamic Governor Switching on Battery

> **Note:** With `amd_pstate=active`, governors function differently than in passive mode. The hardware makes autonomous frequency decisions, and governors act more as hints. The scx_lavd `--autopower` mode provides adaptive power management that may reduce the need for manual governor switching.

This system includes a custom CPU governor switching feature that allows you to dynamically switch between `powersave` and `schedutil` governors while on battery power, without requiring a reboot.

### Features

- **Keyboard shortcuts** for instant switching:
  - `Super+Ctrl+P` → **Performance** mode (schedutil governor)
  - `Super+Ctrl+E` → **Economy** mode (powersave governor)
- **Command-line interface**: `switch-governor [schedutil|powersave]`
- **Visual feedback**:
  - Desktop notifications when switching
  - Ironbar module showing current governor ("󰓅 Performance" or "󰾅 Battery")
- **Battery-only operation**: Only works when on battery power (AC always uses schedutil)
- **Automatic reset**: Resets to powersave (default) after reboot or suspend
- **Passwordless**: No authentication required, configured via sudoers

### Use Cases

**When to use Performance mode (schedutil):**
- Compiling code, building projects
- Video editing or heavy media work
- Running intensive applications (IDEs, browsers with many tabs)
- When system feels sluggish and you need more responsiveness

**When to use Economy mode (powersave):**
- Reading, writing, light browsing
- Watching videos (hardware-accelerated playback)
- Maximum battery life needed
- Default state (automatically set after reboot)

### Implementation Details

**Files:**
- `home-manager/cpu-governor/` - Governor switching module
  - `default.nix` - Module configuration
  - `switch-governor.sh` - Main switching script
  - `set-governor-helper.sh` - Helper script for sysfs writes
- `home-manager/ironbar/modules/cpu-governor/` - Ironbar display module
  - `cpu-governor-status.sh` - Status display script
- `home-manager/niri/binds.nix` - Keyboard shortcut configuration
- `modules/system/core.nix` - Sudoers configuration for passwordless switching

**How it works:**
1. User presses keybinding or runs command
2. Script checks if on battery (exits if on AC)
3. Script calls `set-governor-helper` with sudo (passwordless via sudoers)
4. Helper writes governor to `/sys/devices/system/cpu/cpu*/cpufreq/scaling_governor`
5. Desktop notification shows result
6. Ironbar updates to show current governor

**Security:**
Passwordless sudo is limited to the specific `set-governor-helper` script only, which only writes to CPU governor sysfs files. This is safe because:
- Limited scope (only CPU governor changes)
- No arbitrary command execution
- User already has physical access to the system
- TLP resets to safe defaults on reboot/suspend

## SCX sched_ext Scheduler

This system uses the **SCX (sched_ext)** BPF scheduler framework with **scx_lavd** for adaptive power-aware scheduling.

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
    extraArgs = [ "--autopower" ];
  };
}
```

### Why scx_lavd with --autopower?

**scx_lavd** (Latency-criticality Aware Virtual Deadline) is designed for interactive workloads:

- **Autopower Mode**: Automatically switches between powersave/balanced/performance based on:
  - System's Energy Performance Preference (EPP) - requires `amd_pstate=active`
  - CPU utilization levels
- **Core Compaction**: When CPU usage < 50%, active cores run at higher frequencies while idle cores enter deep C-State sleep
- **Latency-Aware**: Prioritizes latency-critical tasks (UI, input handling)
- **Virtual Deadlines**: Ensures responsive scheduling without starvation

### Available Power Modes

| Flag | Mode | Behavior |
|------|------|----------|
| `--performance` | Performance | Max performance, all cores active |
| `--powersave` | Power Save | Minimize power, use efficient cores |
| `--autopower` | Autopilot | **Automatic switching based on EPP and load** |
| *(none)* | Balanced | Default balanced behavior |

### Alternative Schedulers

- `scx_rusty` - Work-conserving scheduler (good for throughput)
- `scx_bpfland` - General-purpose with tunable parameters
- `scx_simple` - Minimal reference scheduler

### How scx_lavd + AMD P-State Work Together

```
AMD P-State (Active)     →  Controls CPU frequency (hardware autonomous)
         ↓
scx_lavd --autopower     →  Reads EPP, adjusts scheduling behavior
         ↓
Core Compaction          →  Consolidates work to fewer cores when idle
```

Together they provide:
- Adaptive power management based on workload
- Efficient core utilization (idle cores sleep deeply)
- Low-latency scheduling for interactive tasks
- Hardware-controlled frequency scaling

### Verification

```bash
# Check if scx_lavd is running
systemctl status scx

# Check scheduler via sysfs
cat /sys/kernel/sched_ext/root/type
# Should show: lavd

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

Modern AMD laptops support **ACPI platform profiles** for system-wide power/performance settings. This is separate from CPU governor and affects the entire system.

### Available Profiles

| Profile | Description | Use Case |
|---------|-------------|----------|
| `power-saver` | Maximum battery life | Light tasks, reading |
| `balanced` | Default behavior | Normal usage |
| `performance` | Maximum performance | Heavy workloads |

### How It Works

Platform profiles are exposed via `/sys/firmware/acpi/platform_profile` and control:
- Fan curves
- Power limits (TDP)
- GPU performance states
- Charging behavior

### Ironbar Integration

The battery popup in Ironbar includes platform profile switching:
- Click the battery icon in the status bar
- Select desired profile in the popup
- Profile changes immediately (requires polkit authorization)

**Implementation files:**
- `home-manager/ironbar/modules/battery/get-profile.sh` - Reads current profile
- `home-manager/ironbar/modules/battery/set-profile.sh` - Sets profile via pkexec

### Manual Switching

```bash
# Check current profile
cat /sys/firmware/acpi/platform_profile

# List available profiles
cat /sys/firmware/acpi/platform_profile_choices

# Set profile (requires root)
echo balanced | sudo tee /sys/firmware/acpi/platform_profile
```

### Polkit Authorization

Setting platform profiles requires authorization. The set-profile script uses `pkexec` which prompts for the user's password (or fingerprint if configured).

### Relationship to Other Power Settings

| Feature | Scope | What It Controls |
|---------|-------|------------------|
| **Platform Profile** | System-wide | Fan, TDP, GPU, power limits |
| **CPU Governor** | CPU only | Frequency scaling behavior |
| **AMD P-State** | CPU frequency | How quickly CPU scales |
| **TLP** | Power policies | Per-AC/battery settings |
| **SCX Scheduler** | Task scheduling | Which tasks run when/where |

All these work together for optimal power management.

## References

- [Arch Linux Wiki: CPU Frequency Scaling](https://wiki.archlinux.org/title/CPU_frequency_scaling)
- [AMD P-State Driver Documentation](https://www.kernel.org/doc/html/latest/admin-guide/pm/amd-pstate.html)
- [Linux Kernel schedutil Governor](https://docs.kernel.org/scheduler/schedutil.html)
- [sched_ext Documentation](https://github.com/sched-ext/scx)
- [ACPI Platform Profile](https://www.kernel.org/doc/html/latest/userspace-api/sysfs-platform_profile.html)

## Related Files

- `modules/hardware/power-management.nix` - Main power management configuration including AMD P-State mode and TLP settings
- `modules/services/scx.nix` - SCX sched_ext scheduler configuration
- `home-manager/cpu-governor/` - Dynamic governor switching scripts
- `home-manager/ironbar/modules/battery/` - Platform profile switching in status bar
- `home-manager/niri/binds.nix` - Keybindings including `Mod+Ctrl+P` for governor toggle

---

**Last Updated**: 2025-12-23
**Applies To**: Framework Laptop 13 (AMD Ryzen AI 300 Series), NixOS 25.05
