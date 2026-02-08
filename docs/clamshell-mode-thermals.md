# Clamshell Mode Thermal Behavior

This documents the thermal behavior of Framework laptops when operating in clamshell mode (lid closed with external monitor).

## Summary

**This is a known hardware limitation, not a software issue.** The NixOS configuration is optimal and no software changes are needed.

## The Issue

When using the Framework laptop with the lid closed and an external monitor connected, fans run significantly harder than when performing the same tasks with the lid open.

**Temperature difference:** Community reports show 20-30°C higher temperatures in clamshell mode (80-90°C vs ~60°C with lid open).

## Root Cause

The Framework laptop's hinge design restricts exhaust airflow when the lid is closed:

- The black plastic hinge cover extends to the bottom of the chassis
- When closed (180°), exhaust must escape through a small gap with a 90° angle downward
- This severely restricts airflow compared to normal operation

This is a hardware design constraint, not something that can be fixed in software.

## Diagnostics Performed

### Test Results (December 2025)

| Configuration | Max Temp | Fan Speed | Notes |
|---------------|----------|-----------|-------|
| Lid closed, external only @ 144Hz | 69.8°C | ~4000 RPM | Baseline clamshell |
| Lid open, both displays | 81.8°C | 5886 RPM | +55% GPU work |
| Lid open, external only @ 144Hz | 78.8°C | ~4700 RPM | Hotter than closed! |
| Lid open, external only @ 60Hz | 77.8°C | ~4500 RPM | Minor improvement |

### Key Observations

1. **4K @ 144Hz is the primary heat source** - The external display alone generates significant GPU load
2. **Two displays adds substantial load** - Both displays active pushes temps to 81°C
3. **Lid open isn't always cooler** - In testing, lid open actually ran hotter with the same workload
4. **Refresh rate has minor impact** - 60Hz only reduced temps by ~1°C

### System State During Tests

| Metric | Value | Assessment |
|--------|-------|------------|
| Internal display (eDP-1) | Disabled when lid closed | Correct behavior |
| GPU utilization | 3-5% idle | Not the cause |
| Power profile | balanced | Correct |
| monitor-hotplug service | 12ms total CPU in 24h | Negligible |

The diagnostics confirm:
- Internal display properly disabled when lid closed
- No extra processes running in clamshell mode
- GPU/CPU not working harder in clamshell
- High-resolution, high-refresh external display is a significant heat contributor

## Workarounds

### For 4K @ 144Hz External Display

1. **Accept elevated temps as normal** - 4K @ 144Hz is demanding on the iGPU
2. **Reduce refresh rate when not gaming** - 60Hz saves ~1°C but loses smoothness
3. **Disable internal display when not needed** - Reduces GPU load by ~37%

### For Clamshell Mode (Community-Tested)

1. **Crack lid open ~45°** - Allows exhaust to escape normally
2. **Elevated stand** - Helps with bottom intake airflow
3. **Vertical laptop stand** - Some users report acceptable temps
4. **Thermal paste reapplication** - Reduces base temps but doesn't fix airflow issue

### Why Opening the Lid Helps

The hinge cover blocks the exhaust at 180° (fully closed). Opening even slightly allows hot air to escape without requiring the 90° turn through the restricted gap.

**Note:** In our testing, the benefit of opening the lid was offset by enabling the internal display. For best thermal performance with an external monitor, keep the lid open but disable the internal display via `niri msg output eDP-1 off`.

## Configuration Verification

These settings are already optimal in this configuration:

### Lid Behavior
- **Normal mode (no Happy):** `HandleLidSwitch = "suspend"` - Lid close suspends the system
- **Docked mode:** `HandleLidSwitchDocked = "ignore"` - Lid close with external monitor doesn't suspend
- **Happy active:** Inhibits `handle-lid-switch` to prevent suspend during remote development

### Display Management
The internal display (eDP-1) is automatically disabled when the lid is closed via a dedicated service:

- **Service:** `lid-switch-display.service` (systemd user service)
- **Mechanism:** Listens to ACPI events via `acpi_listen` (bypasses systemd-logind)
- **Works with Happy:** Functions even when Happy inhibits systemd-logind's lid handling
- **Initial state:** Checks lid state on startup and disables display if already closed
- **Event-driven:** No polling, responds immediately to lid open/close events

### Power Management
TLP with appropriate settings for Framework laptops.

### Relevant Files
- `modules/system/core.nix` - Lid handling, acpid service
- `modules/hardware/power-management.nix` - TLP configuration
- `home-manager/nixos/niri/lid-switch-display.sh` - Display control script
- `home-manager/nixos/niri/default.nix` - lid-switch-display service
- `home-manager/nixos/happy/default.nix` - Happy inhibit configuration

## Framework Community References

- [Clamshell mode increases CPU temps substantially](https://community.frame.work/t/clamshell-mode-increases-cpu-temps-substantially/21707)
- [Extreme overheating with lid closed](https://community.frame.work/t/extreme-burning-overheating-with-the-lid-closed/13983)
- [Performance with lid closed](https://community.frame.work/t/performance-with-lid-closed/26387)
- [Closed clamshell vertical use and heat feedback](https://community.frame.work/t/closed-clamshell-vertical-use-and-heat-feedback/22244)

## Optional Software Mitigations

These provide minor benefits but don't solve the fundamental airflow issue:

### Reduce External Display Refresh Rate
Change from 144Hz to 60Hz when docked to reduce GPU cycles. Trade-off: less smooth display.

### More Aggressive Power Profile
Switch to `low-power` platform profile when docked. Trade-off: reduced performance.

Neither is recommended as the impact is minimal compared to the physical workarounds above.
