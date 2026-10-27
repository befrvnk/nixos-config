# MediaTek MT7925 WiFi Boot Failure

> **Three separate issues:** boot-time "driver own failed", runtime throughput
> throttling after suspend/resume, and the **7.1+ mt76 MLO traffic-stall regression**.
> The ASPM workaround addresses the first two; it is not a fix for the MLO regression.

## Summary

The MediaTek MT7925 (WiFi 7) card on Framework Laptop 13 (AMD Ryzen AI 300 Series) intermittently fails to initialize during boot with "driver own failed" errors. This is caused by PCIe ASPM (Active State Power Management) putting the device in a low-power state before the driver can probe it.

**Status (2026-10-27):** `performance` is the conservative fallback. The current
default is `powersave` (L1 enabled, less aggressive than `powersupersave`).
A/B on 6.18.55: performance 10.32 W, powersave 7.17 W, powersupersave 5.90 W,
with L1 on the NVMe/Wi-Fi/GPU links and no short-run throughput loss. The
powersave boot/suspend-resume soak is pending; powersupersave is the next trial.
Fall back to `performance` if the old symptoms return.

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
"pcie_aspm.policy=powersave"   # current compromise; "performance" is the fallback
```

`powersave` enables L1 (better battery than `pcie_aspm=off`) while avoiding the
most aggressive substates. `performance` remains the conservative fallback if
the card regresses. Requires a reboot to take effect.

### Immediate diagnostic (no reboot)

To confirm a stuck card is the cause, reset the driver (drops WiFi briefly):

```bash
sudo modprobe -r mt7925e && sleep 2 && sudo modprobe mt7925e
curl -o /dev/null -s -w '%{speed_download}\n' --max-time 15 \
  'https://speed.cloudflare.com/__down?bytes=10000000'
```

If throughput jumps back to normal after the reload, the card was in a degraded
driver/ASPM state — the conservative ASPM policy prevents it from recurring.

## 7.1.x Kernel mt76 Regression (WiFi dies while "connected")

**Checked 2026-10-22:** a candidate fix was posted and successfully tested, but is
absent from the inspected Linux **7.3**, Linux **7.2.12** and CachyOS **7.3.0-2**
sources. Do not treat those release numbers as proof that this regression is fixed.
Keep CachyOS LTS as the default; see the dated findings and upgrade guidance below.

**Updated 2026-10-26:** the candidate fix is now **merged into mainline** as
[`dd3f17ef69ed`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=dd3f17ef69ed6d0085cd94a15b9dec227b4ebfb1)
("wifi: mt76: mt7925: keep MLD membership consistent during link add", committed by
Felix Fietkau; carries `Fixes: ff643b81bc38` and both independent testers'
`Tested-by`). regzbot now reports the regression resolved in mainline
([tracker](https://linux-regtracking.leemhuis.info/regzbot/regression/lore/066b30cc-a9e6-4aeb-964d-71551e8ea3ef@posteo.de/)).

Source verification repeated the 10-22 method against today's trees: `mt7925/mcu.c`
in `master` contains the pending-link logic (9 matches), `v7.3` contains none — so
the release table below still holds. The commit carries **no `Cc: stable`**, so 7.3.y
point releases are not expected to receive it; the first released kernel with the fix
should be **7.4** (kernel.org's latest stable was still 7.3 on 2026-10-26).

Chaotic-Nyx availability on 2026-10-26: `linuxPackages_cachyos-lts` = **6.18.55**
(the running kernel), `linuxPackages_cachyos`/`-bore`/`-lto`/`-rc` = **7.3.0** — none
of them contain the fix. Upgrade guidance below therefore stands: stay on 6.18 LTS
until a fixed build is packaged, then re-check `mt7925_mcu_sta_mld_tlv()` for the
pending-link argument and run your own MLO soak before promoting.

[Bugzilla 221884](https://bugzilla.kernel.org/show_bug.cgi?id=221884) still shows NEW
with its last update on August 18. The later investigation and patch testing moved
to the mailing list, so the stale Bugzilla status alone is not the basis for this
recommendation.

### Symptom

- WiFi stays *visually connected* with healthy-looking link (good RSSI, rates)
- But all traffic dies: no ARP/ICMP, gateway unreachable, throughput ~0
- Pings degrade progressively (e.g. 9 ms → 300–1400 ms → 0 bytes)
- **Reloading `mt7925e` restores connectivity** (until the next occurrence)
- Affects kernel 7.1.x (confirmed on 7.1.1 through 7.1.8, incl. CachyOS)
- **Also reproduced on 7.2.0-rc7** (twice, same signature — not fixed in 7.2 rc7)
- **Known-good reports:** LTS 6.18.38/6.18.40; 6.18.42 confirmed clean for 3+ h
  with MLO active. This is evidence for those tested setups, not a guarantee for
  every later LTS point release or firmware/AP combination.

### Root cause (from Bugzilla 221884)

- Silent **WFDMA0 TX hardware queue stall**: `xmit-queues` debugfs shows the
  `tail` pointer frozen while `head` keeps advancing — packets enqueue but the
  firmware stops draining. RX counters freeze at the same instant.
- Correlates with an active **6 GHz MLO link** (5 GHz + 6 GHz); fully disabling
  the 6 GHz radio on the AP eliminates the freeze.
- The driver keeps reporting a healthy link (0 tx retries, 0 tx failed, good
  RSSI), so nothing is logged to dmesg at the time of the stall.

### October 2026 investigation and candidate fix

The reporter bisected the first bad commit to
[`ff643b81bc38`](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=ff643b81bc38eaff6c0ab783a62e4ba9e10d2476),
"wifi: mt76: mt7925: pass mlink and mconf to sta_mld_tlv()". Vanilla 7.0 was a
clean baseline in that investigation; the regression appeared in 7.1.

On **October 4**, Andrei Rusu de Castro submitted
[PATCH v2: keep MLD membership consistent during link add](https://lore.kernel.org/linux-wireless/20261004-mt7925-mld-v2-248bb5e6404f@empyreal.works/).
It carries an explicit pending secondary link through both station updates so
firmware receives a consistent link description before the new link is published.

The original reporter manually applied v2 **on top of 7.3-rc5** and reported
46 minutes without a stall on MT7925 PCIe, firmware `20260813113118`, FritzBox
5690 Pro and active 5+6 GHz MLO. Both links stayed active during about 4.2 GB RX
and 340 MB TX. Another tester reported improvements on MT7925U USB hardware.
See the [testing replies](https://lore.kernel.org/linux-wireless/20261004-mt7925-mld-v2-248bb5e6404f@empyreal.works/T/#t).

**"7.3-rc5 + v2" means a custom-patched test build. It does not mean the patch
was included in the official RC.** Submission, Tested-by replies, maintainer merge
and inclusion in a released tag are separate events. Linux 7.3 was released on
October 18, but its source still lacks this candidate change.

The October 22 source review compared `mt7925_mcu_sta_mld_tlv()` in:

| Released source | Finding |
|---|---|
| Linux 7.3 | Old secondary-only encoding; no pending-link argument |
| Linux 7.2.12 | Same function implementation as Linux 7.3 |
| CachyOS 7.3.0-2 (`c46eff6c5747`) | Same function implementation as Linux 7.3 |

This verifies absence of the candidate in the inspected code, not a new hardware
reproduction on every release. No WiFi reset, network reconfiguration, kernel
switch or hardware test was performed during this research.

A third tester's October 5 report also cautions against blindly applying v2 to
an older base: **7.2.8 + v2 alone failed MLO handshakes** on their setup; v2 plus
seven additional mt76 fixes passed a single 15-minute run. Their setup also included
a wpa_supplicant 2.11 MLO group-key backport (`b048a294a`). They did not isolate which
accompanying driver fixes were required or whether v2 caused the handshake failure.
A custom backport needs dependency review and its own hardware validation, not just
successful patch application.

### Version inventory at the October 22 check

| Scope | Version | Meaning |
|---|---|---|
| Running Framework kernel | 6.18.42-cachyos | Still booted at inspection |
| Repository-selected CachyOS LTS | 6.18.52 | Full Framework build passed after the origin rebase; not boot/WiFi acceptance |
| Pinned provider's `cachyos-latest` | 7.2.8 | Not a candidate for an unpatched default switch |
| Pinned provider's `cachyos-rc` | 7.3-rc4 | Older than the custom RC5 test; the release number does not include v2 |
| Latest upstream mainline release | 7.3 | Candidate absent in inspected source |
| Latest upstream 7.2 stable | 7.2.12 | Candidate absent in inspected source |
| Latest upstream 6.18 LTS | 6.18.58 | Announced upstream; not supplied by the currently inspected CachyOS provider |

The provider's public `release` version manifest still advertised 7.2.8/6.18.52/
7.3-rc4 at this check. Updating a flake input is not proof that a newer or fixed
kernel becomes available. Distinguish provider availability, a successful build,
the currently booted kernel and actual WiFi test results.

### Re-test and promotion criteria

- Prefer a conservative update within **6.18 LTS**; the configured 6.18.52 is
  already built. Activation/reboot and validation remain user-operated steps.
- Do not promote an unpatched 7.x release just because it is newer or an unrelated
  MT7925 fix landed. Verify inclusion of this candidate or a reviewed equivalent
  in the exact upstream/CachyOS source being built.
- For an experimental patched 7.3 trial, review dependent fixes and firmware/AP
  assumptions, retain a known-good LTS boot entry and recovery networking, and let
  the user validate sustained 5+6 GHz MLO traffic, scanning and suspend/resume.
- Preserve the independent ASPM workaround. Neither a patch post nor another
  machine's Tested-by report establishes this Framework's runtime acceptance.

### Not the same bug: AP-switch download collapse (FIXED in 7.2-rc1)

A separate mt76 regression — download drops to 2–5 Mbit/s after switching
between a wifi 6 and a wifi 5 AP (no MLO involved) — was **fixed upstream by
[commit b2f5def2f133](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=b2f5def2f133fca12897b0fc707a8d3df1c3cb05),
first shipped in 7.2-rc1**. If you read that "7.2 fixes MT7925", it refers to
this one — it is NOT the freeze tracked in this repo.

### Sources

- [CachyOS Forum: MT7925 WiFi 7 MLO breaks connectivity on 7.1.x](https://discuss.cachyos.org/t/mt7925-wifi-7-mlo-breaks-connectivity-on-7-1-x-mt76-regression/31972)
- [Kernel Bugzilla 221884](https://bugzilla.kernel.org/show_bug.cgi?id=221884)
- [CachyOS Forum: AP-switch download collapse (fixed upstream, not in 7.1)](https://discuss.cachyos.org/t/mt7925-wifi-drops-to-a-few-mbit-s-after-switching-aps-on-7-1-x-fixed-upstream-not-in-7-1/34131)
- [Upstream fix for related TDLS collapse: commit 37d6538](https://github.com/torvalds/linux/commit/37d65384aa6f)
  ("don't disable AP BSS when removing TDLS peer") — merged + Cc stable,
  symptom: downlink collapses to 6–72 Mbit/s until a manual reconnect
- [openwrt/mt76 #1108](https://github.com/openwrt/mt76/issues/1108): contention-
  triggered latency collapse on 5 GHz (kernel 7.1.3, same firmware, NixOS)
- [October 4 candidate v2 and testing thread](https://lore.kernel.org/linux-wireless/20261004-mt7925-mld-v2-248bb5e6404f@empyreal.works/T/#t)
- [Released Linux 7.3 driver source](https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c?h=v7.3)
- [Released Linux 7.2.12 driver source](https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c?h=v7.2.12)
- [CachyOS 7.3.0-2 driver source at its release commit](https://github.com/CachyOS/linux/blob/c46eff6c57477ecbe6a55cea2641d07f58543630/drivers/net/wireless/mediatek/mt76/mt7925/mcu.c)
- [Upstream release inventory](https://www.kernel.org/)
- [Chaotic-Nyx CachyOS kernel packaging](https://github.com/chaotic-cx/nyx)

### Fix applied in this repo

`hosts/framework/default.nix` retains this selection rather than automatically
selecting `cachyos-latest`:

```nix
boot.kernelPackages =
  inputs.chaotic.legacyPackages.${pkgs.stdenv.hostPlatform.system}."linuxPackages_cachyos-lts";
```

The kernel is packaged by Chaotic-Nyx and instantiated from *their* nixpkgs pin, so it
resolves to the paths `nyx-cache.chaotic.cx` actually holds (`shared/caches.nix`). It
replaces the `nix-cachyos-kernel` overlay, whose only binary cache was the Lantian
endpoint revoked in `docs/security-hardening.md`.

The origin rebase advanced the configured LTS to 6.18.52 and its full system build
passed; the running kernel was still 6.18.42 during this check.

The October research changed neither kernel selection nor lock files. Revisit a
7.x default only after verifying the relevant fix in the exact selected source and
passing user-operated WiFi tests. The available `cachyos-rc` package is not by itself
evidence of a fix; a custom candidate must remain a separate reversible trial.

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

## Conservative Fallback

> **2026-10-27:** this is the conservative fallback. The current default is
> `powersave`; see the status note at the top. `performance` remains the
> rollback if the card regresses.

**Location:** `modules/hardware/power-management.nix`

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
| `pcie_aspm.policy=performance` | All PCIe | Early boot | 10.32 W (2026-10-27 A/B) | ✅ Conservative fallback |
| `pcie_aspm.policy=powersave` | All PCIe | Early boot | 7.17 W; L1 enabled | ✅ Current default, boot/resume soak pending |
| `pcie_aspm.policy=powersupersave` | All PCIe | Early boot | 5.90 W; L1 enabled | ⚠️ Old MT7925 bug; next trial |

The watt figures are from one A/B run on 6.18.55, not a general guarantee.

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
