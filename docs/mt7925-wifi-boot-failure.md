# MediaTek MT7925 WiFi Boot Failure

> **Also covers (same fix):** runtime dramatic-throughput throttling after
> suspend/resume and the **7.1.x kernel mt76 regression** (see dedicated
> sections below).

## Summary

The MediaTek MT7925 (WiFi 7) card on Framework Laptop 13 (AMD Ryzen AI 300 Series) intermittently fails to initialize during boot with "driver own failed" errors. This is caused by PCIe ASPM (Active State Power Management) putting the device in a low-power state before the driver can probe it.

**Status:** Fixed with `pcie_aspm.policy=performance` kernel parameter.

## Runtime Throughput Throttling (slow internet after resume)

**Same underlying cause as the boot failure: aggressive `powersupersave` ASPM.**

### Symptom

- Internet is (intermittently) very slow after suspend/resume.
- The radio looks completely healthy: `iw dev wlp192s0 link` shows a full
  negotiated rate (e.g. `tx 780 Mbit/s VHT-MCS 9`), signal ~-49 dBm,
  `power_save off`, `beacon loss: 0`.
- But real throughput is terrible (~2.7 Mbit/s): `curl` a 10 MB file from
  `speed.cloudflare.com` times out at 15 s pulling ~337 KB/s (0.3% of nominal).
- Restarting NetworkManager / toggling the connection / restarting
  systemd-resolved does **not** help.
- `pcie_aspm.policy=powersupersave` is active on the kernel cmdline.

### Why it happens

`powersupersave` is the most aggressive ASPM policy. After recovery, the MT7925
wakes and negotiates a normal MCS rate, but aggressive PCIe L1 power management
leaves HW frame aggregation (A-MPDU/AMSDU) throttled — high negotiated speed,
terrible delivered throughput. The Stub-resolver first query is also slow
(~300 ms) reinforcing a feeling of sluggishness, but the dominant issue is the
radio data path.

### Fix

Change the ASPM policy away from `powersupersave` in
`modules/hardware/power-management.nix`:

```nix
"pcie_aspm.policy=performance"   # was powersupersave
```

`performance` keeps ASPM enabled (better battery than `pcie_aspm=off`) while
avoiding the aggressive low-power state. Requires a reboot to take effect.

### Immediate diagnostic (no reboot)

To confirm a stuck card is the cause, reset the driver (drops WiFi briefly):

```bash
sudo modprobe -r mt7925e && sleep 2 && sudo modprobe mt7925e
curl -o /dev/null -s -w '%{speed_download}\n' --max-time 15 \
  'https://speed.cloudflare.com/__down?bytes=10000000'
```

If throughput jumps back to normal after the reload, the card was in a degraded
driver/ASPM state — the `performance` policy prevents it from recurring.

## 7.1.x Kernel mt76 Regression (WiFi dies while "connected")

**Status:** Unfixed upstream in 7.1.x. Workaround: use the CachyOS LTS kernel.

### Symptom

- WiFi stays *visually connected* with healthy-looking link (good RSSI, rates)
- But all traffic dies: no ARP/ICMP, gateway unreachable, throughput ~0
- Pings degrade progressively (e.g. 9 ms → 300–1400 ms → 0 bytes)
- **Reloading `mt7925e` restores connectivity** (until the next occurrence)
- Affects kernel 7.1.x (confirmed on 7.1.1 through 7.1.6, incl. CachyOS)
- **Not affected: LTS kernel 6.18.38+ works perfectly** (community-confirmed)

### Sources

- [CachyOS Forum: MT7925 WiFi 7 MLO breaks connectivity on 7.1.x](https://discuss.cachyos.org/t/mt7925-wifi-7-mlo-breaks-connectivity-on-7-1-x-mt76-regression/31972)
- [Upstream fix for related TDLS collapse: commit 37d6538](https://github.com/torvalds/linux/commit/37d65384aa6f)
  ("don't disable AP BSS when removing TDLS peer") — merged + Cc stable,
  symptom: downlink collapses to 6–72 Mbit/s until a manual reconnect
- [openwrt/mt76 #1108](https://github.com/openwrt/mt76/issues/1108): contention-
  triggered latency collapse on 5 GHz (kernel 7.1.3, same firmware, NixOS)

### Fix applied in this repo

`hosts/framework/default.nix`: `boot.kernelPackages` switched from
`linuxPackages-cachyos-latest` (7.1.x, affected) to
`linuxPackages-cachyos-lts` (6.18.x, confirmed working).

Revisit when the regression is fixed upstream (bugzilla report pending), then
return to `linuxPackages-cachyos-latest`.

## The Problem

### Symptoms

- WiFi interface not appearing after boot (`ip a` shows only loopback)
- Reboots often fail, cold boot (shutdown → start) more reliable
- Sometimes causes instant system reboot during driver initialization
- Issue is intermittent - works after multiple reboots

### Error Messages

From `journalctl -b -k | grep mt7925`:

```
mt7925e 0000:c0:00.0: driver own failed
mt7925e 0000:c0:00.0: probe with driver mt7925e failed with error -5
```

Error -5 is `EIO` (I/O error) - the driver cannot communicate with the device.

### Hardware

- **WiFi Card:** MediaTek MT7925 (RZ717) Wi-Fi 7 160MHz
- **PCI Address:** `0000:c0:00.0`
- **Driver:** `mt7925e`
- **Laptop:** Framework Laptop 13 (AMD Ryzen AI 300 Series)
- **Kernel:** 6.18.0

## Root Cause Analysis

### What is "driver own"?

When the mt7925e driver probes the device, it must take control from the card's internal firmware. This "driver own" handshake requires the device to be responsive. If PCIe ASPM has put the device into a deep sleep state (L1), the device may not respond.

### The Race Condition

```
Boot Sequence (Failing):
1. BIOS initializes PCIe, possibly leaving device in low-power state
2. Kernel enables ASPM with aggressive policy (powersupersave)
3. Device enters L1 sleep state
4. mt7925e driver probes device
5. Driver calls "driver own" handshake
6. Device unresponsive → "driver own failed" → error -5

Boot Sequence (Working):
1. BIOS initializes PCIe
2. Device happens to be in accessible state (L0)
3. mt7925e driver probes device
4. Driver successfully takes ownership
5. WiFi works
```

### Why Cold Boot Works Better

Cold boot (full shutdown → power on) fully resets the PCIe device. Warm reboot may leave residual power state that isn't properly cleared by BIOS.

## Solutions Attempted

### 1. Module Parameter: `mt7925e.disable_aspm=1`

**Configuration:**
```nix
boot.extraModprobeConfig = ''
  options mt7925e disable_aspm=1
'';
```

**Result:** ❌ Did not fix the issue

**Why it failed:** The module parameter is applied during driver probe, but by that time the device is already in an inaccessible state. Log evidence showed:

```
mt7925e 0000:c0:00.0: disabling ASPM  L1    ← Parameter IS working
mt7925e 0000:c0:00.0: driver own failed     ← But too late!
```

The parameter correctly disables ASPM, but the device was already unresponsive before the driver even loaded.

### 2. Kernel Parameter: `pcie_aspm=off`

**Configuration:**
```nix
boot.kernelParams = [ "pcie_aspm=off" ];
```

**Result:** ✅ Fixed the issue

**Why it works:** This kernel parameter takes effect very early in boot, before PCI device enumeration. The device never enters a low-power state.

**Downside:** Disables ASPM for ALL PCIe devices, increasing power consumption by ~1-2W.

### 3. Kernel Parameter: `pcie_aspm.policy=performance` (Final Solution)

**Configuration:**
```nix
boot.kernelParams = [ "pcie_aspm.policy=performance" ];
```

**Result:** ✅ Fixed the issue

**Why it works:** Sets a conservative ASPM policy that avoids aggressive power states while still allowing some power management. Takes effect early in boot like `pcie_aspm=off`.

**Advantage over `pcie_aspm=off`:** Lower power impact while still preventing the boot failure.

## Final Solution

**Location:** `hosts/framework/default.nix`

```nix
# MediaTek MT7925 WiFi: Set conservative ASPM policy to prevent "driver own failed"
# errors during boot. The WiFi card fails to initialize if aggressive ASPM puts it
# in a low-power state before driver probe. Module-level disable_aspm=1 was too late.
# "performance" keeps ASPM enabled but avoids aggressive power states.
# If this still fails, fall back to "pcie_aspm=off".
boot.kernelParams = [ "pcie_aspm.policy=performance" ];
```

## Comparison of ASPM Options

| Option | Scope | When Applied | Power Impact | Reliability |
|--------|-------|--------------|--------------|-------------|
| `mt7925e.disable_aspm=1` | WiFi only | Driver probe | Minimal | ❌ Too late |
| `pcie_aspm=off` | All PCIe | Early boot | Higher (~1-2W) | ✅ Works |
| `pcie_aspm.policy=performance` | All PCIe | Early boot | Lower | ✅ Works |

## Debugging Tools

### wifi-debug Script

A devenv script was created to capture diagnostic information when WiFi fails:

```bash
wifi-debug
```

This captures:
- `dmesg.log` - Kernel messages
- `kernel-wifi.log` - WiFi-related kernel logs
- `networkmanager.log` - NetworkManager logs
- `full-boot.log` - Complete boot journal
- `ip-addr.log` / `ip-link.log` - Network interface state
- `modules.log` - Loaded WiFi modules
- `pci-network.log` - PCI network devices

**Important:** Run this BEFORE rebooting when WiFi fails to capture the logs from the failed boot.

### Checking Previous Boot Logs

```bash
# List available boots
journalctl --list-boots

# Check specific boot for WiFi errors
journalctl -b -1 -k | grep -i -E "(mt7925|driver own|probe.*failed)"

# Check for crashes (short boot sessions)
journalctl --list-boots | tail -20  # Look for very short durations
```

### Verifying Current ASPM Policy

```bash
# Check current ASPM policy
cat /sys/module/pcie_aspm/parameters/policy

# Check kernel command line
cat /proc/cmdline | grep -o 'pcie_aspm[^[:space:]]*'
```

## Related Issues

### TLP ASPM Configuration

The system uses TLP for power management with these ASPM settings in `modules/hardware/power-management.nix`:

```nix
PCIE_ASPM_ON_AC = "default";
PCIE_ASPM_ON_BAT = "powersupersave";
```

These TLP settings apply at runtime AFTER boot, so they don't cause the initial boot failure. However, `powersupersave` on battery is very aggressive. If WiFi issues occur during runtime (not just boot), consider changing to `default`.

### Known Upstream Issues

This is a known issue with MediaTek MT792x series WiFi cards on Linux:

- [Framework Community: MediaTek issues on AMD/Linux](https://community.frame.work/t/responded-yet-more-mediatek-issues-on-amd-linux/50039)
- [Ubuntu Bug #1955882: MT7921 ASPM affects power consumption](https://bugs.launchpad.net/ubuntu/+source/linux/+bug/1955882)
- [Kernel patch: fix possible probe failure after reboot](https://lkml.kernel.org/stable/20220405070408.012479780@linuxfoundation.org/)
- [Arch Forums: MT7921E driver crashes](https://bbs.archlinux.org/viewtopic.php?id=304655)

## Future Considerations

### Monitoring for Upstream Fix

A proper fix should come from:
1. MediaTek driver improvements (better retry logic, delay before probe)
2. Kernel PCIe subsystem changes
3. BIOS/firmware updates from Framework

Check periodically if newer kernels or Framework BIOS updates address this issue, which would allow removing the kernel parameter.

### If Issue Returns

If WiFi boot failures return:
1. Run `wifi-debug` before rebooting to capture logs
2. Check `journalctl -b -1 -k | grep mt7925` for error messages
3. Try escalating to `pcie_aspm=off` if `performance` policy stops working
4. Check for BIOS updates from Framework
5. Check kernel changelogs for mt7925e driver changes

## Investigation Log

**Date:** 2025-12-12

### Timeline

1. **Initial Report:** WiFi not working after reboot, only loopback visible
2. **Investigation:** Found "driver own failed" errors in boot logs
3. **Identified Hardware:** MediaTek MT7925 (not Intel AX210 as initially suspected)
4. **First Attempt:** `mt7925e.disable_aspm=1` - Failed (too late in boot)
5. **Second Attempt:** `pcie_aspm=off` - Success (2 reboots)
6. **Final Solution:** `pcie_aspm.policy=performance` - Success (3+ reboots)

### Key Evidence

Boot logs showing module parameter working but failing:
```
Dec 12 17:14:27 framework kernel: mt7925e 0000:c0:00.0: disabling ASPM  L1
Dec 12 17:14:28 framework kernel: mt7925e 0000:c0:00.0: driver own failed
Dec 12 17:14:28 framework kernel: mt7925e 0000:c0:00.0: probe with driver mt7925e failed with error -5
```

This proved the module parameter was taking effect but was too late - the device was already inaccessible.

### System Configuration

- **ASPM Policy (before fix):** `powersupersave` (most aggressive)
- **Kernel ASPM Default:** `CONFIG_PCIEASPM_DEFAULT=y` (uses BIOS policy)
- **Firmware:** Present at `/run/current-system/firmware/mediatek/mt7925/`

**Investigated by:** Claude Code
