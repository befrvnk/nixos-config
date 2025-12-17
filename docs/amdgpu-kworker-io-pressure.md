# AMDGPU kworker Stuck Causing High I/O Pressure

This document describes an issue where the AMD GPU driver causes kernel worker threads to become stuck, resulting in extremely high I/O pressure readings despite minimal actual disk activity.

## Symptoms

### What You'll See

1. **Extremely high I/O pressure** (80-90%+ in `/proc/pressure/io`) with near-zero actual disk I/O
2. **kworker threads in D-state** (uninterruptible sleep):
   ```
   kworker/u97:*+events_unbound
   ```
3. **Workqueue rescue threads activating** (visible in stack traces as `rescuer_thread`)
4. **System feels sluggish** despite low CPU and memory pressure
5. **Fan running due to perceived load**

### Diagnosis

```bash
# Check PSI metrics - I/O should be near 0% when idle
cat /proc/pressure/io
# Bad: some avg10=85.00 avg60=80.00 avg300=75.00

# Check for blocked processes
vmstat 1 3
# Look at 'b' column (blocked) - should be 0

# Find D-state processes
for pid in /proc/[0-9]*; do
  state=$(cut -d' ' -f3 "$pid/stat" 2>/dev/null)
  if [ "$state" = "D" ]; then
    comm=$(cat "$pid/comm" 2>/dev/null)
    echo "PID ${pid##*/}: $comm"
  fi
done

# Get stack trace of blocked kworker (requires root)
sudo cat /proc/$(pgrep -f 'kworker.*events_unbound' | head -1)/stack
```

### Stack Trace Pattern

When this issue occurs, the stack trace shows:
```
[<0>] rescuer_thread+0x39d/0x4b0
[<0>] kthread+0xf8/0x250
[<0>] ret_from_fork+0x196/0x1d0
[<0>] ret_from_fork_asm+0x1a/0x30
```

The `rescuer_thread` indicates the workqueue system has detected stuck workers and activated rescue mode.

## Understanding the Metrics

### What is PSI (Pressure Stall Information)?

PSI tracks how much time processes spend waiting for resources:
- **some**: At least one task was stalled
- **full**: ALL non-idle tasks were stalled (critical)
- **avg10/60/300**: Percentage over 10s/60s/5min windows

### Normal vs Abnormal Values

| Level | Value | Description |
|-------|-------|-------------|
| Normal | 0-5% | Healthy idle system |
| Acceptable | 5-10% | Light workload |
| Moderate | 10-30% | Active batch processing |
| High | 30-50% | Heavy workload |
| **Critical** | >50% | Severe bottleneck |

**Key insight**: High PSI I/O pressure with low actual disk I/O (`bi`/`bo` in vmstat near 0) indicates processes are blocking on something OTHER than disk - like a stuck driver.

## Root Cause

### The AMDGPU Display Code Issue

The amdgpu driver has a timeout issue in the display management code:

1. `dmub_srv_wait_for_idle()` function gets stuck waiting
2. This blocks the `events_unbound` workqueue
3. The kernel's workqueue system detects stuck workers
4. Rescue threads activate, but can't resolve the underlying issue
5. PSI counts all this blocking as "I/O pressure"

### Why PSI Reports This as I/O

The kernel's Pressure Stall Information system doesn't distinguish between:
- Actual disk I/O waits
- Workqueue thread blocking
- Driver-level waits

Any process in uninterruptible sleep (D-state) contributes to I/O pressure metrics.

## Affected Systems

| Component | Affected |
|-----------|----------|
| **Hardware** | Framework 13 (AMD 7040), Framework 13 (AMD AI 300), Framework 16, ASUS TUF Gaming A15, devices with Navi 33/Phoenix1 GPUs |
| **Kernels** | Multiple versions (6.x series) |
| **Scenario** | External displays, clamshell mode, high refresh rate monitors |

## Solution

### Kernel Parameter

Add to your kernel command line:

```
amdgpu.dcdebugmask=0x10
```

### NixOS Configuration

```nix
boot.kernelParams = [
  "amdgpu.dcdebugmask=0x10"
];
```

This parameter adjusts the display code debugging mask and prevents the deadlock condition that causes workers to get stuck.

### Alternative Parameters

If the above doesn't help, these may also be relevant:

```nix
boot.kernelParams = [
  "amdgpu.dcdebugmask=0x10"  # Primary fix
  # Additional options if needed:
  # "amdgpu.runpm=0"         # Disable runtime power management
  # "amdgpu.aspm=0"          # Disable ASPM for GPU
  # "amdgpu.bapm=0"          # Disable bidirectional application power management
];
```

## Verification

After applying the fix and rebooting:

```bash
# I/O pressure should drop significantly
cat /proc/pressure/io
# Expected: some avg10=0.00-5.00 avg60=0.00-5.00 avg300=0.00-5.00

# No blocked processes
vmstat 1 3
# 'b' column should be 0

# No D-state kworkers
ps -eo pid,state,comm | grep " D "
# Should return nothing or very brief transient entries
```

## Observed Results

Testing on Framework 13 (AMD AI 300 Series) in clamshell mode with USB-C external monitor:

| Metric | Before Fix | After Fix (Expected) |
|--------|------------|----------------------|
| I/O Pressure (avg10) | ~80-90% | <5% |
| Blocked kworkers | Persistent | None |
| vmstat 'b' column | 4-5 | 0 |
| System responsiveness | Sluggish | Normal |

## Related Issues

This issue often co-occurs with:

1. **UCSI USB-C errors** - See `docs/ucsi-usbc-io-pressure.md`
   - Blacklist `ucsi_acpi` and `typec_ucsi` modules
   - Reduces I/O pressure by ~10-15%

2. **VPE Queue Reset on Suspend** (kernel 6.18)
   - Use kernel 6.17 or wait for 6.19 fix
   - Documented in `hosts/framework/default.nix`

3. **MT7925 WiFi Boot Failures** - See `docs/mt7925-wifi-boot-failure.md`
   - Use `pcie_aspm.policy=performance`

## Technical Details

### Workqueue Architecture

```
┌─────────────────────────────────────────────────────┐
│                 User Processes                       │
└────────────────────┬────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│              Kernel Workqueues                       │
│  ┌─────────────────────────────────────────────┐    │
│  │  events_unbound (WQ_UNBOUND)                │    │
│  │  - Runs on any CPU                          │    │
│  │  - Used for long-running tasks              │    │
│  │  - amdgpu display updates go here           │    │
│  └─────────────────────────────────────────────┘    │
│                     │                                │
│         ┌───────────┴───────────┐                   │
│         ▼                       ▼                   │
│  ┌─────────────┐         ┌─────────────┐           │
│  │   Worker    │         │   Rescuer   │           │
│  │   Thread    │  stuck  │   Thread    │ activated │
│  │ (kworker/u) │ ──────► │             │           │
│  └─────────────┘         └─────────────┘           │
└─────────────────────────────────────────────────────┘
                     │
┌────────────────────▼────────────────────────────────┐
│              AMDGPU Driver                          │
│  ┌─────────────────────────────────────────────┐   │
│  │  dmub_srv_wait_for_idle()                   │   │
│  │  - Waits for display microcontroller        │   │
│  │  - Timeout not working properly             │   │
│  │  - Worker thread blocks here ← PROBLEM      │   │
│  └─────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Why dcdebugmask=0x10 Helps

The `dcdebugmask` parameter controls debug/behavior flags in the Display Core (DC) component:
- Bit 4 (0x10) adjusts timing or retry behavior in display updates
- This prevents the deadlock condition in `dmub_srv_wait_for_idle()`
- The exact mechanism isn't publicly documented but empirically works

## References

1. [Arch Forums: kworker stuck waiting in amdgpu driver](https://bbs.archlinux.org/viewtopic.php?id=299561)
2. [Linux Kernel PSI Documentation](https://docs.kernel.org/accounting/psi.html)
3. [Linux Workqueue Documentation](https://docs.kernel.org/core-api/workqueue.html)
4. [ArchWiki: AMDGPU](https://wiki.archlinux.org/title/AMDGPU)
5. [PSI Numbers and Meanings](https://utcc.utoronto.ca/~cks/space/blog/linux/PSINumbersAndMeanings)

## History

| Date | Event |
|------|-------|
| 2024 | Issue first reported on Framework AMD laptops |
| 2024 | `amdgpu.dcdebugmask=0x10` workaround discovered |
| December 2025 | Documented for Framework 13 AMD AI 300 series |
