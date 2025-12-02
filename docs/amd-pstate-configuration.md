# AMD P-State CPU Frequency Scaling Configuration

## Overview

This document explains the AMD P-State configuration used in this NixOS setup, including what Energy Performance Preference (EPP) is, why we use Passive mode instead of Active mode, and the performance benefits achieved.

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

## Solution: Switch to Passive Mode

### Changes Made

#### 1. Kernel Parameter
Added to `modules/hardware/power-management.nix`:
```nix
boot.kernelParams = [
  "nmi_watchdog=0"
  "amd_pstate=passive"  # ← Added this
];
```

This forces the system to use `amd-pstate` driver (Passive mode) instead of `amd-pstate-epp` (Active mode).

#### 2. CPU Governor Configuration
Changed TLP settings in `modules/hardware/power-management.nix`:
```nix
# Before:
CPU_SCALING_GOVERNOR_ON_AC = "performance";

# After:
CPU_SCALING_GOVERNOR_ON_AC = "schedutil";
```

The `schedutil` governor:
- Integrates directly with Linux scheduler
- Makes frequency decisions based on scheduler run queue data
- Scales CPU frequency up/down based on actual workload
- More responsive than `ondemand` while more efficient than `performance`

#### 3. Removed EPP Settings
Removed these lines (only relevant for Active mode):
```nix
# No longer needed in Passive mode
CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
```

## Results

### Verification After Reboot
```bash
$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver
amd-pstate  # ✅ Changed from amd-pstate-epp

$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_available_governors
performance schedutil  # ✅ schedutil now available

$ cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
schedutil  # ✅ Active governor
```

### Performance Improvement
Measured over 60-second idle periods on 4K@144Hz external monitor:

| Metric | Before (performance) | After (schedutil) | Improvement |
|--------|---------------------|-------------------|-------------|
| Average CPU | 4.63% | 2.58% | **-44%** |
| Peak CPU | 16.8% | 7.9% | **-53%** |

### Why This Works Better

1. **Dynamic Frequency Scaling**: schedutil adjusts CPU frequency based on scheduler load, allowing the CPU to idle at lower frequencies when Niri compositor has nothing to do

2. **Scheduler Integration**: schedutil sees the scheduler's view of workload, which is more accurate than autonomous hardware decisions for desktop workloads

3. **Lower Baseline**: Instead of staying at high frequencies "just in case" (performance mode), schedutil only boosts frequency when the scheduler indicates actual work

## Trade-offs

### Passive Mode Advantages
- ✅ Better idle power consumption
- ✅ Lower CPU usage for compositors/idle workloads
- ✅ More predictable behavior
- ✅ Full governor choice (schedutil, ondemand, conservative)
- ✅ Better integration with Linux scheduler

### Passive Mode Disadvantages
- ⚠️ Slightly higher latency on workload spikes (few microseconds)
- ⚠️ More kernel overhead (but negligible on modern systems)
- ⚠️ Doesn't leverage CPU's autonomous frequency control capabilities

### When Active Mode Would Be Better
Active mode (`amd-pstate-epp`) would be preferable if:
- BIOS/firmware properly exposes all EPP preferences (`balance_performance`, `power`, etc.)
- Running server workloads where hardware knows best
- Battery life is critical and hardware power management is well-tuned
- Future BIOS updates improve EPP support on Framework laptops

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

### If BIOS Updates Improve EPP Support
If future Framework BIOS updates expose more EPP preferences:
1. Could test switching back to Active mode with `amd_pstate=active`
2. Configure EPP via TLP:
   ```nix
   CPU_ENERGY_PERF_POLICY_ON_AC = "balance_performance";
   CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
   ```
3. Compare power consumption and responsiveness

### Alternative Governors to Test
In Passive mode, you can experiment with:
- `ondemand` - More aggressive frequency scaling, higher power use
- `conservative` - More gradual frequency scaling, better battery
- `powersave` - Lowest possible frequencies (for extreme battery saving)

To test (runtime, no reboot needed):
```bash
echo ondemand | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

## References

- [Arch Linux Wiki: CPU Frequency Scaling](https://wiki.archlinux.org/title/CPU_frequency_scaling)
- [AMD P-State Driver Documentation](https://www.kernel.org/doc/html/latest/admin-guide/pm/amd-pstate.html)
- [Linux Kernel schedutil Governor](https://docs.kernel.org/scheduler/schedutil.html)

## Related Files

- `modules/hardware/power-management.nix` - Main power management configuration including AMD P-State mode and TLP settings
- `modules/hardware/framework.nix` - Framework-specific hardware configuration (if exists)

---

**Last Updated**: 2025-12-02
**Applies To**: Framework Laptop 13 (AMD Ryzen AI 300 Series), NixOS 26.05
