# UCSI/USB-C High I/O Pressure Issue on Framework Laptops

This document describes a known issue affecting Framework laptops running Linux kernels 6.9+ that causes high I/O pressure, blocked kernel worker processes, and log spam related to the USB Type-C Connector System Software Interface (UCSI).

## Symptoms

### What You'll See

1. **High I/O pressure** (80-90%+ in `/proc/pressure/io`) despite low actual disk activity
2. **Blocked kworker processes** in D-state (uninterruptible sleep):
   ```
   kworker/u97:*+events_unbound
   ```
3. **Kernel log spam** during boot and USB-C events:
   ```
   ucsi_acpi USBC000:00: unknown error 0
   ucsi_acpi USBC000:00: GET_CABLE_PROPERTY failed (-5)
   ucsi_acpi USBC000:00: unknown error 256
   ucsi_acpi USBC000:00: UCSI_GET_PDOS failed (-5)
   ```
4. **Fan running constantly** due to perceived system load
5. **Suspend/resume issues** with USB-C devices connected

### Diagnosis Commands

```bash
# Check I/O pressure (should be near 0% when idle)
cat /proc/pressure/io

# Check for blocked processes
ps aux | awk '$8 ~ /D/ {print}'

# Check vmstat for blocked column (b)
vmstat 1 5

# Check kernel logs for UCSI errors
journalctl -k | grep -i ucsi
```

## Root Cause

### The Problem

Two intersecting issues cause this behavior:

1. **Kernel Regression (Linux 6.9+)**: A patch introduced in kernel 6.9 attempts to query USB-C cable properties using the `GET_CABLE_PROPERTY` command. This is part of the UCSI specification for reporting cable capabilities.

2. **Framework Firmware Limitation**: Framework's embedded controller (EC) and power delivery (PD) controller don't properly support the `GET_CABLE_PROPERTY` command. They return error codes 0 and 256, which per the UCSI spec indicate "command not supported."

### Why This Causes I/O Pressure

The `ucsi_acpi` driver handles USB-C connector change events via kernel workqueues. When the driver queries cable properties and receives errors:

1. The workqueue thread (`kworker/u97:*+events_unbound`) blocks waiting on the UCSI subsystem
2. The kernel's pressure stall information (PSI) counts these blocked processes as I/O stalls
3. Even though no actual disk I/O is occurring, the system reports high I/O pressure
4. Multiple processes can become blocked, creating a backlog

### The Offending Kernel Patch

The issue was introduced by kernel commit related to:
```
[PATCH v4 2/4] usb: typec: ucsi: Register cables based on GET_CABLE_PROPERTY
```

This patch implements USB-C cable capability detection that doesn't work properly with Framework's USB-C controller firmware.

## Affected Systems

| Component | Affected Versions |
|-----------|------------------|
| **Hardware** | Framework 13 (AMD 7040), Framework 13 (AMD AI 300), Framework 16, Framework 13 (Intel Core Ultra) |
| **Kernels** | 6.9+ (confirmed through 6.17) |
| **BIOS** | All versions including latest (3.03, 3.05+) |
| **Distros** | All Linux distributions (NixOS, Arch, Fedora, Ubuntu, etc.) |

## Solution: Blacklist UCSI Modules

### NixOS Configuration

Add to your host configuration (e.g., `hosts/framework/default.nix`):

```nix
boot.blacklistedKernelModules = [ "ucsi_acpi" "typec_ucsi" ];
```

### Other Distributions

Create `/etc/modprobe.d/blacklist-ucsi.conf`:
```
blacklist ucsi_acpi
blacklist typec_ucsi
```

Then regenerate initramfs:
```bash
# Arch/Manjaro
mkinitcpio -P

# Fedora/RHEL
dracut --force

# Ubuntu/Debian
update-initramfs -u
```

### Kernel Command Line (Temporary)

For testing, add to your kernel command line:
```
module_blacklist=ucsi_acpi,typec_ucsi
```

## Side Effects of Blacklisting

### What Still Works

- USB-C data transfer (USB 2.0/3.0/4.0)
- USB-C charging (basic level)
- DisplayPort Alt Mode (external monitors)
- Thunderbolt devices (basic functionality)

### What May Be Lost

- **PD Negotiation Reporting**: OS won't receive detailed power delivery status
- **Advanced Alt Mode Management**: Some systems may lose DisplayPort Alt Mode (varies by hardware)
- **Charging Status Notifications**: Less detailed power delivery information
- **Sleep/Wake Reliability**: Some users report improved suspend/resume

In practice, most Framework users report **no noticeable functional difference** after blacklisting.

## Alternative Workarounds

### Option 1: Use Kernel 6.6 LTS

```nix
boot.kernelPackages = pkgs.linuxPackages_6_6;
```

This kernel predates the problematic UCSI patch.

### Option 2: Full Power Cycle

Per Framework staff, this temporarily resets the EC state:
1. Power down completely
2. Unplug ALL power sources (charger, USB devices)
3. Wait 90 seconds
4. Restart

This is temporary and the issue will return.

### Option 3: Wait for Firmware Fix

Framework is aware of and tracking this issue. A firmware update may eventually address the underlying EC/PD controller behavior.

## Clamshell Mode Considerations

When using the laptop in clamshell mode with an external USB-C monitor:

1. The UCSI driver constantly queries cable properties for the connected display
2. With the lid closed, the internal display driver may enter an inconsistent state
3. The combination can trigger more frequent UCSI queries and failures
4. Blacklisting the modules is especially recommended for clamshell setups

## Official Tracking

### Framework Resources

- **GitHub Issue Tracker**: [ucsi_acpi USBC000:00: unknown error 0 - Issue #3](https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker/issues/3)
- **Community Thread**: [USB C Error on boot](https://community.frame.work/t/usb-c-error-on-boot/52012)
- **Community Thread**: [UCSI_GET_PDOS failed](https://community.frame.work/t/ucsi-acpi-usbc000-ucsi-get-pdos-failed-5/69163)
- **Resolved Thread**: [Linux 6.8.2 UCSI ACPI Errors On Sleep](https://community.frame.work/t/resolved-linux-6-8-2-ucsi-acpi-errors-on-sleep-device-change/47846)

### Linux Kernel Resources

- **Kernel Source**: [ucsi_acpi.c](https://github.com/torvalds/linux/blob/master/drivers/usb/typec/ucsi/ucsi_acpi.c)
- **USB Mailing List**: Discussions about GET_CABLE_PROPERTY implementation

### Distribution-Specific

- **NixOS Wiki**: [Framework Laptop 16](https://wiki.nixos.org/wiki/Hardware/Framework/Laptop_16)
- **ArchWiki**: [Framework Laptop 13](https://wiki.archlinux.org/title/Framework_Laptop_13)
- **NixOS Discourse**: [Broken Framework laptop drivers on 6.11 kernel](https://discourse.nixos.org/t/broken-framework-laptop-drivers-on-6-11-kernel/52302)

## Technical Deep Dive

### UCSI Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Linux Kernel                            │
├─────────────────────────────────────────────────────────────┤
│  typec_ucsi (core driver)                                   │
│       │                                                     │
│       ├── ucsi_acpi (ACPI interface) ← problematic module   │
│       │       │                                             │
│       │       └── Queries GET_CABLE_PROPERTY                │
│       │               │                                     │
│       │               ▼                                     │
├───────┴───────────────────────────────────────────────────┤
│  ACPI / Platform Firmware                                   │
│       │                                                     │
│       ▼                                                     │
│  Embedded Controller (EC)                                   │
│       │                                                     │
│       ▼                                                     │
│  USB Power Delivery Controller                              │
│       │                                                     │
│       └── Returns error 0/256 (not supported)               │
└─────────────────────────────────────────────────────────────┘
```

### Workqueue Blocking

When `ucsi_handle_connector_change()` is called:

1. The function runs in a kernel workqueue context
2. It attempts to query cable properties via ACPI
3. The EC returns an error after a timeout
4. The workqueue thread is blocked during this wait
5. PSI (Pressure Stall Information) counts this as I/O pressure
6. Multiple concurrent queries create multiple blocked workers

### Error Code Meanings

| Error Code | UCSI Spec Meaning |
|------------|-------------------|
| 0 | Command not supported / Unknown error |
| 256 | Command not supported (alternate encoding) |
| -5 | Linux ACPI error (EIO - I/O error) |
| -95 | Linux ACPI error (EOPNOTSUPP - Operation not supported) |
| -110 | Linux ACPI error (ETIMEDOUT - Connection timed out) |

## Observed Results

Testing on Framework 13 (AMD AI 300 Series) in clamshell mode with USB-C external monitor:

| Metric | Before Blacklist | After Blacklist |
|--------|------------------|-----------------|
| I/O Pressure (avg10) | ~85-90% | ~75-77% |
| UCSI errors in logs | Yes (constant) | **None** |
| Blocked kworkers | Persistent | Intermittent |
| `/sys/class/typec/` | Present | Removed |

### Key Observations

1. **Partial Fix**: The blacklist reduces I/O pressure by ~10-15% and eliminates UCSI error spam
2. **Residual Blocking**: Some blocking may persist from the Thunderbolt subsystem managing the external monitor connection
3. **Functional**: USB-C charging, DisplayPort Alt Mode, and Thunderbolt all continue to work
4. **Log Cleanup**: The `ucsi_acpi: unknown error 0` messages are completely eliminated

### Clamshell Mode Note

In clamshell mode with USB-C monitor, some I/O pressure (~75%) may be normal due to the Thunderbolt subsystem actively managing the connection. This is separate from the UCSI issue and may not indicate a problem if the system feels responsive.

## Verification

After applying the blacklist and rebooting:

```bash
# Verify modules are not loaded
lsmod | grep ucsi
# Should return nothing

# Verify TypeC sysfs is removed (expected with blacklist)
ls /sys/class/typec/
# Should return "No such file or directory"

# Check I/O pressure (may still show ~75% in clamshell mode)
cat /proc/pressure/io

# Check for UCSI errors (should be none)
journalctl -k | grep -i ucsi
# Should return nothing

# Verify USB-C still works
# - Plug in charger → should charge
# - Connect monitor → should display
# - Connect USB device → should work
```

## History

| Date | Event |
|------|-------|
| March 2024 | Kernel patch for GET_CABLE_PROPERTY introduced |
| June 2024 | Linux 6.9 released with the patch |
| June 2024 | First reports of UCSI errors on Framework laptops |
| September 2024 | Framework acknowledges issue in GitHub tracker |
| December 2025 | Issue remains open, blacklisting recommended |

## Related Issues

- **VPE Queue Reset on Suspend**: See kernel 6.18 amdgpu bug (separate issue)
- **MT7925 WiFi Boot Failure**: See `docs/mt7925-wifi-boot-failure.md` (separate ASPM issue)
- **Clamshell Mode Thermals**: See `docs/clamshell-mode-thermals.md`

## References

1. Framework Software/Firmware Issue Tracker: https://github.com/FrameworkComputer/SoftwareFirmwareIssueTracker
2. Linux UCSI Driver Source: https://github.com/torvalds/linux/tree/master/drivers/usb/typec/ucsi
3. USB Type-C Connector System Software Interface Specification (UCSI)
4. Framework Community Forums: https://community.frame.work
5. Arch Linux Forums UCSI Discussions: https://bbs.archlinux.org
