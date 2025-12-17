# AMDGPU Display Driver and High I/O Pressure

This document describes two distinct issues with the AMD GPU driver that cause elevated I/O pressure readings:

1. **Stuck kworker issue** - A deadlock in `dmub_srv_wait_for_idle()` causing workers to block indefinitely (fixable with `dcdebugmask=0x10`)
2. **VRR workqueue overhead** - Normal, expected behavior when Variable Refresh Rate is enabled (not a bug, just elevated PSI metrics)

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

## Issue 2: VRR Workqueue Overhead (Expected Behavior)

### What is VRR?

Variable Refresh Rate (VRR), also known as FreeSync/Adaptive Sync, allows the display to dynamically adjust its refresh rate to match GPU frame output. This eliminates screen tearing without the input lag of traditional VSync.

### Why VRR Causes Elevated PSI

When VRR is enabled, the AMD driver calls `dm_handle_vmin_vmax_update()` via workqueue for every VUPDATE signal (once per frame):

1. **VUPDATE signals** occur during VBlank at refresh-rate frequency (~60-66 times/second at 60Hz)
2. Each signal triggers a workqueue task to adjust Vmin/Vmax timing boundaries
3. The workqueue task acquires `dc_lock` mutex and calls `dc_stream_adjust_vmin_vmax()`
4. PSI counts these brief workqueue waits as "I/O pressure"

### This is By Design

Per kernel patches, the workqueue approach is intentional:
> "offload the call to `dc_stream_adjust_vmin_vmax()` to a workqueue thread instead of directly calling it from the interrupt handler, such that it waits for dc_lock"

This prevents race conditions with DMUB (Display Microcontroller Unit) commands.

### Diagnosing VRR Workqueue Activity

```bash
# Enable workqueue tracing (requires root)
echo 1 | sudo tee /sys/kernel/debug/tracing/events/workqueue/workqueue_execute_start/enable
echo 1 | sudo tee /sys/kernel/debug/tracing/tracing_on

# Capture 5 seconds of activity
sleep 5
sudo cat /sys/kernel/debug/tracing/trace | grep dm_handle_vmin_vmax_update | wc -l
# Expected with VRR: ~300-330 calls (60Hz * 5 seconds)

# Disable tracing
echo 0 | sudo tee /sys/kernel/debug/tracing/tracing_on
```

### Expected PSI Values with VRR

| VRR State | Expected I/O Pressure | System Feel |
|-----------|----------------------|-------------|
| **VRR disabled** | 0-5% | Normal |
| **VRR enabled** | 40-70% | Normal (elevated PSI is expected) |
| **VRR + stuck kworker bug** | 80-95% | Sluggish |

**Key insight**: With VRR enabled, PSI I/O of 40-70% is normal and does not indicate a performance problem. The system should feel responsive despite the elevated metrics.

### VRR vs Stuck Kworker: How to Tell the Difference

| Indicator | VRR Overhead (Normal) | Stuck Kworker (Bug) |
|-----------|----------------------|---------------------|
| System feel | Responsive | Sluggish |
| `dm_handle_vmin_vmax_update` calls | ~60/sec (consistent) | Variable or stalled |
| Stack trace | Normal completion | `rescuer_thread` active |
| PSI I/O | 40-70% stable | 80-95%+ increasing |

### Parameters That Don't Help VRR Overhead

We tested several kernel parameters that do NOT reduce VRR workqueue overhead:

```nix
# These don't help with VRR overhead (don't use for this purpose):
boot.kernelParams = [
  # "amdgpu.gfxoff=0"  # Tested: No effect on call frequency, increases power use
  # "amdgpu.runpm=0"   # Disables runtime PM, doesn't affect VRR
];
```

### Recommendation for VRR Users

**Accept the elevated PSI metrics.** If your system feels responsive:
- The high I/O pressure is a reporting artifact, not a real bottleneck
- VRR provides smoother visuals that outweigh the cosmetic PSI numbers
- Only disable VRR if you specifically need PSI metrics for monitoring purposes

To disable VRR (if needed):
```nix
# In your niri/outputs.nix or equivalent:
variable-refresh-rate = false;
```

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

### Phase 1: Initial State (Multiple Issues)

| Metric | Value | Cause |
|--------|-------|-------|
| I/O Pressure | ~85-90% | UCSI errors + stuck kworker + VRR |
| System feel | Sluggish | Actual bottleneck |
| UCSI errors | Constant spam | Framework EC firmware limitation |

### Phase 2: After UCSI Blacklist

| Metric | Value | Change |
|--------|-------|--------|
| I/O Pressure | ~75-77% | ↓ 10-15% improvement |
| UCSI errors | None | ✓ Eliminated |

### Phase 3: After dcdebugmask=0x10

| Metric | Value | Change |
|--------|-------|--------|
| I/O Pressure | ~50-68% | ↓ Further improvement |
| System feel | Responsive | ✓ No longer sluggish |
| Stuck rescuer_thread | None | ✓ Fixed |

### Phase 4: VRR Investigation

| Test | Result |
|------|--------|
| `dm_handle_vmin_vmax_update` frequency | 333 calls/5 sec (~66/sec) |
| `amdgpu.gfxoff=0` tested | No change in call frequency |
| VRR disabled (theoretical) | Would drop to <5% |

### Final State (VRR Enabled)

| Metric | Value | Status |
|--------|-------|--------|
| I/O Pressure | 40-70% | Expected with VRR |
| System feel | Responsive | ✓ Normal |
| `dm_handle_vmin_vmax_update` | ~66/sec | Expected (matches refresh rate) |

**Conclusion**: The remaining 40-70% PSI I/O pressure is expected behavior when VRR is enabled. The system is functioning correctly.

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

### Stuck kworker Issue
1. [Arch Forums: kworker stuck waiting in amdgpu driver](https://bbs.archlinux.org/viewtopic.php?id=299561)
2. [Linux Kernel PSI Documentation](https://docs.kernel.org/accounting/psi.html)
3. [Linux Workqueue Documentation](https://docs.kernel.org/core-api/workqueue.html)

### VRR Implementation
4. [Linux Kernel DCN Overview](https://docs.kernel.org/gpu/amdgpu/display/dcn-overview.html) - VUPDATE signal documentation
5. [Kernel Patch: Prevent vblank irq disable while VRR is active](https://patchwork.kernel.org/project/dri-devel/patch/20190322200428.4008-2-mario.kleiner.de@gmail.com/)
6. [AMDGPU Display Manager Source](https://github.com/torvalds/linux/blob/master/drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c)
7. [ArchWiki: Variable Refresh Rate](https://wiki.archlinux.org/title/Variable_refresh_rate)

### General
8. [ArchWiki: AMDGPU](https://wiki.archlinux.org/title/AMDGPU)
9. [PSI Numbers and Meanings](https://utcc.utoronto.ca/~cks/space/blog/linux/PSINumbersAndMeanings)

## History

| Date | Event |
|------|-------|
| 2024 | Stuck kworker issue first reported on Framework AMD laptops |
| 2024 | `amdgpu.dcdebugmask=0x10` workaround discovered |
| December 2025 | Documented for Framework 13 AMD AI 300 series |
| December 2025 | VRR workqueue overhead identified as expected behavior |
| December 2025 | Tested `amdgpu.gfxoff=0` - confirmed no effect on VRR overhead |
