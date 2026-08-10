# WiFi Wake-up Logging (slow internet after suspend/resume)

## Purpose

Diagnose an intermittent issue where, after waking from suspend/resume, the
internet can be very slow even though the WiFi connection and network look
healthy. The likely culprit is the MediaTek MT7925 radio not fully re-awakening
(runtime counterpart to the boot-time ASPM issue in
[mt7925-wifi-boot-failure.md](mt7925-wifi-boot-failure.md)).

The module snapshots the radio state just before suspend and again ~5s after
resume, writes both to the journal, and diffs them so a degraded or partially
woken device is easy to spot.

## What it captures

Around every sleep cycle, on the `sleep.target` (the same hook mechanism NixOS
uses for `powerManagement.resumeCommands`):

- `ip link show <if>` — is the interface up, and did it bounce on resume?
- `iw dev <if> get power_save` — is power-save still forced on after wake?
- `iw dev <if> link` — signal (RSSI) and negotiated tx rate before vs after
- PCIe link state (`lspci -vv` `LnkSta:` / `ASPM`) — did the link downgrade?
- Default route presence
- A 3-packet ping to the default gateway for an end-to-end latency baseline

The post-resume pass also prints a `diff` between the two snapshots (timestamp
headers ignored) so state changes across suspend are immediately visible.

## Where the data lives

Output goes to the journal of the `wifi-wakeup-log` unit:

```bash
sudo journalctl -u wifi-wakeup-log            # all cycles
sudo journalctl -u wifi-wakeup-log -n 200 -f  # tail, live
```

There is also a devenv shortcut:

```bash
devenv shell
wifi-wakeup-log          # last 200 lines
wifi-wakeup-log -f       # follow live
```

Raw snapshots are also cached under `/var/lib/wifi-wakeup/` (pre-suspend.log /
post-resume.log) for scripting/analysis.

## Reading the output

- `!! interface '<if>' missing (module did not wake?)` — the radio did not
  re-probe; likely the firmware-level wake failure (the harsh case).
- `LnkSta:` downgraded between pre- and post-resume (e.g. `8 GT/s -> 2.5 GT/s`)
  — PCIe re-negotiated to a lower speed after wake.
- `power_save on` in post-resume but the AC profile should have disabled it —
  power-save got stuck on after resume.
- A much higher ping latency than pre-suspend on a *healthy* link points to the
  radio needing time to re-negotiate → consider lengthening `SETTLE_DELAY`.

## Configuration

- Module: `modules/services/wifi-wakeup-log.nix`
- Script: `modules/services/wifi-wakeup-log.sh`
- Enabled via `modules/profiles/desktop.nix`
- Only active on hosts that set `wifiInterface` (currently the Framework).
- The post-resume settle delay is `5s` by default; override with the
  `SETTLE_DELAY` environment variable on the unit if the link needs more time.

## Notes / future work

- `SETTLE_DELAY` is read from the environment of the `resume` invocation; it is
  currently not exposed as a Nix option (kept minimal). Promote it to a
  `services.wifiWakeupLog` option if tuning is needed.
- Once a pattern is confirmed, the follow-up fix depends on the failure mode:
  - Radio not re-probing → escalate the ASPM/`disable_aspm` approach used for
    the boot issue, applied at runtime.
  - Power-save stuck → force `iw … set power_save off` in the resume hook.
  - **PCIe link downgrade / throughput throttling → resolved by relaxing ASPM**
    away from `powersupersave` to `performance` in `power-management.nix`
    (root cause found 2026-08-10: see mt7925-wifi-boot-failure.md).