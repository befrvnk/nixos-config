# Quickshell Migration Plan: Replacing Ironbar with a Custom Niri Shell

> Historical: the custom shell is superseded by the native Noctalia V5 configuration.
> It remains in the repository for rollback, but is no longer imported.
> Current setup: [Noctalia V5 with Niri](./noctalia-niri-overview.md).

Status: **COMPLETE (custom modules) — now exploring Quickshell native modules.**
Ironbar fully replaced by a custom Quickshell overview-only bar. Option B visibility.
All 16 modules ported; popup positioning fixed (recomputes on open, clamped to screen).
Evaluating replacing custom modules with Quickshell built-in services before any Go rewrite.

### Native-module migration (in progress)
- **Volume → Quickshell.Services.Pipewire** (native reactive volume/mute) — DONE
- **Battery → Quickshell.Services.UPower** for display; profile switch stays tuned scripts — DONE
- Tray/Clock already native (SystemTray/SystemClock).
- **WiFi → Quickshell.Networking** (WifiDevice/WifiNetwork/connect/PSK) — DONE (scripts kept as fallback)
- **Bluetooth → Quickshell.Bluetooth** (adapter/device/connect/disconnect/pair) — DONE (scripts kept as fallback)
- **Peripheral battery → Quickshell.Services.UPower.devices** — DONE (mouse/keyboard/gaming + generic non-laptop battery)
- Notifications → Quickshell.Services.Notifications: not migrated; it is a notification server and would conflict with dunst.
- Openrouter/firewall/aurora/weather/sysinfo/storage have no native equivalent
  (external APIs / system parsing) — keep custom scripts or a future Go binary.

### Cutover notes
- `home-manager/nixos/ironbar` is no longer imported (no ironbar service). Scripts stay on disk
  as source for custom script-based modules, and for API-fetch modules (openrouter/weather/etc.).
- `darkman` now restarts `quickshell.service` on theme switch.
- Volume is now native Pipewire; `volume-ctl`/cache may no longer be needed (decide later).

## Phase 4 cutover checklist (done)
- Remove `home-manager/nixos/ironbar` import from `frank.nix` (keep the quickshell import).
- Remove the `ironbar` systemd user service (goes away transitively with the module).
- **Keep** `niri/volume-ctl.sh` + `volume-status` cache: Quickshell Volume module reads
  `Config.volumeStatus` which reads that cache (event-driven, no PipeWire polling).
- `niri/startup.nix`: keep `volume-ctl init` (seeds cache Quickshell reads). Update its comment.
- `darkman/darkman-switch-mode.sh`: change `restart ironbar.service` → `restart quickshell.service`
  so the shell reloads its generated Config.qml (theme colors) on dark/light toggle.
- Comments in power-management.nix / bluetooth.nix / packages.nix / binds.nix that say
  "for ironbar" can be reworded to "for the bar" (non-functional).
- Optional: archive `home-manager/nixos/ironbar/` to `docs/ironbar-archive/` for reference.
- Update `docs/quickshell-migration-plan.md` to **Done** and update the ironbar overview doc.

## Locked Decisions (from review)
1. **Bar is overview-only** — implemented via **Option B**: `visible: niri.overview.isOpen`
   (native qml-niri binding, no toggle helper). Fall back to **Option A** (toggle script)
   only if the Phase 0 runtime gate shows surface-toggle artifacts.
2. **WiFi password:** inline QML prompt (simplest to implement — collect password in the popup, pass to `nmcli`).
3. **Bluetooth:** fully new QML backed by `bluetoothctl`/bluez D-Bus — no third-party widget (no suitable ready-made one for niri, and a custom one keeps Stylix theming).
4. **Notifications:** keep it minimal — a count indicator + clear-all. No deeper interactions.

## Goal

Replace ironbar (currently used as an overview-only bar driven by a toggle script and
systemd service) with a **custom Quickshell-based shell**. Requirements:

- **Same information on the bar** — all 16 current ironbar modules, same placement
  (`start`/`center`/`end`), same content.
- **Better interactivity** — turn static popups into reactive, real UI:
  - **WiFi:** list of available networks with per-network connect/disconnect + password dialog.
  - **Display:** brightness slider, rotation/resolution/refresh, ABM + stay-on + redlight toggles.
  - **Bluetooth:** device list with connect/pair/disconnect.
  - **Battery:** power-profile radio selector, live details.
  - **Volume:** real slider instead of read-only popup label.
- **Built with the custom-module engine** Quickshell provides (QML + JS), not a JSON config.

## Why Quickshell (decided)

- Stock **`quickshell` 0.3.0** is in nixpkgs; no flake fork needed.
- Built-in **status notifier** service covers the current `tray` module.
- Built-in **PipeWire** service gives a real volume/brightness slider (no popup workaround).
- **`qml-niri`** plugin (or `niri msg --json`) provides workspace/window data.
- Layer-shell windows, popups, focus-grab, and animations are first-class.
- Avoids ironbar's static-text + `on_click:run` model that makes interactive UIs (wifi lists,
  sliders, radio selectors) nearly impossible.
- Avoids the **Noctalia fork**, which was archived (Jul 2026) — build on stock instead.

## Module Inventory → Mapping

Current `config.json` regions (main bar order preserved):

| Region | Ironbar module | New Quickshell approach |
|---|---|---|
| start | openrouter (button+popup) | Text widget wrapping existing scripts; popup panel |
| start | firewall (conditional) | Text widget wrapping existing scripts; popup panel |
| start | sys_info (cpu/mem/temp) | Text widget wrapping existing scripts (diagnostic poll) |
| center | aurora (conditional) | Text widget wrapping existing scripts; popup panel |
| center | weather (conditional) | Text widget wrapping existing scripts; forecast popup |
| center | clock | QML clock label (`%H:%M`) |
| center | notifications | **NEW native:** dunst history + count via D-Bus, clear-all button |
| end | tray | Quickshell **status notifier** service |
| end | storage (conditional) | Popup list with open + eject buttons (reuse scripts) |
| end | wifi | **NEW interactive panel: network list + connect/password** |
| end | bluetooth | **NEW interactive** — device list + connect/pair (ironbar's built-in bluetooth currently used) |
| end | peripheral-battery | Text widget wrapping existing scripts |
| end | volume | **NEW interactive** — Quickshell PipeWire slider + wire to `volume-ctl` cache |
| end | display | **NEW interactive** — brightness slider + rotation/res, toggle toggles, reuse scripts |
| end | battery | **NEW interactive** — details + power-profile radio (reuse scripts) |

Legend: ✅ = reuse script as-is; 🔄 = port/adapt; ⛰ = fully new custom UI.

## Overview-Only Behavior

The bar must only appear during Niri's overview (workspace switcher) mode, matching the
current ironbar design. Two options:

- **A. Toggle-script pattern**: adapt `toggle-ironbar.py` → `toggle-shell.sh`, which
  subscribes to Niri's `OverviewOpenedOrClosed` event and calls Quickshell IPC to show/hide the
  bar. Systemd `ExecStart` runs the toggle script (mirrors current `ironbar.service`). Self-healing.
- **B. Native QML (PRIMARY — try first):** `qml-niri` exposes a reactive
  **`niri.overview.isOpen`** property, event-driven via the IPC socket (no polling, no extra
  process). Bind the bar's visibility directly:

  ```qml
  PanelWindow {          // Quickshell layer-shell top bar
      // when overview is NOT open, hide the bar (unmaps layer surface)
      visible: niri.overview.isOpen
      Niri { id: niri; Component.onCompleted: connect() }
  }
  ```

  **Fallback:** Option B is the chosen path. If toggling the surface via `visible` shows
  artifacts (bar flickering, exclusive-zone space not released when hidden, or click-through
  issues), **fall back to Option A** — the toggle-script/systemd approach is already proven in
  this repo. The concrete fallback trigger and decision gate are in **Phase 0** & **Phase 5**.

### Why Option B is expected to work
- `PanelWindow` wraps `zwlr_layer_shell_v1` and manages `wl_surface` lifecycle;
  runtime changes to `exclusiveZone`/`anchors` are pushed to the compositor (per the official
  Quickshell book). Hiding the window unmaps the surface, so the other windows re-layout and the
  reserved top space is released — the same clean-unmap behavior ironbar achieved via IPC.
- `qml-niri` tracks overview state in real time through the same event stream the current
  `toggle-ironbar.py` subscribes to.
- No extra process, no IPC round-trips per show/hide, and a single QML binding is dramatically
  simpler than the current toggle script.

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                Niri Compositor                            │
│   workspace/window state via niri msg / qml-niri        │
└────────────────────────┬─────────────────────────────────┘
                         │ layer-surface + xdg-layer-shell
┌────────────────────────▼─────────────────────────────────┐
│        quickshell (stock 0.3.0)  —  QML shell           │
│  ├─ bar.qml       layer-shell top bar window           │
│  ├─ services.qml  pipewire, statusNotifier, niri       │
│  └─ modules/       one QML file per bar module          │
└────────────────────────┬─────────────────────────────────┘
                         │ Path + IPC
┌────────────────────────▼─────────────────────────────────┐
│  existing ironbar module scripts (reused)               │
│  + new QML-native interactors (wifi/nmcli, slider, etc.)│
└──────────────────────────────────────────────────────────┘
```

## Proposed File Layout

```
home-manager/nixos/quickshell/
├── default.nix            # home-manager module: package, services, theme wiring
├── quickshell.nix          # (if split) package/entrypoint definition
├── config/
│   ├── main.qml            # root: instantiates bar window + modules
│   ├── bar.qml              # layer-shell bar window (top)
│   ├── popup.qml            # reusable popup window type
│   ├── styles.qml           # Stylix/Catppuccin color + theme helpers
│   └── modules/
│       ├── openrouter.qml
│       ├── firewall.qml
│       ├── sysinfo.qml
│       ├── aurora.qml
│       ├── weather.qml
│       ├── clock.qml
│       ├── notifications.qml
│       ├── tray.qml
│       ├── storage.qml
│       ├── wifi.qml          # NEW interactive (network list → connect)
│       ├── bluetooth.qml     # NEW interactive (device list → connect/pair)
│       ├── peripheral.qml
│       ├── volume.qml        # NEW interactive (PipeWire slider)
│       ├── display.qml       # NEW interactive (brightness + res/rot/toggles)
│       └── battery.qml       # interactive (profile selector)
├── modules/                  # MIRROR of reused ironbar scripts for parity during migration
│   └── (symlink/copy from ironbar/modules/)
```

## Implementation Phases

### Phase 0 — Scaffold and smoke test (no behavior change)
- Add `quickshell` 0.3.0 from the **qml-niri flake** (it builds quickshell with the `Niri` plugin
  baked in) or add `qml-niri` as an input and provide both.
- Create `home-manager/nixos/quickshell/default.nix` with `systemd.user.services.quickshell`
  (`PartOf/After graphical-session.target`, `ConditionEnvironment=WAYLAND_DISPLAY`,
  `ExecStartPre=-pkill -f quickshell`). Ensure `NIRI_SOCKET` is available to the service.
- Create a minimal `main.qml` with a top `PanelWindow` bar (static label + clock) and wire the
  **Option B overview binding** (`visible: niri.overview.isOpen`).
- Wire `quickshell` into `home-manager/nixos/frank.nix` imports.
- **Do NOT touch ironbar yet.** Verify the new shell runs alongside it via
  `systemctl --user restart quickshell`.
- **Option B decision gate:** open/close Overview. If the bar shows/hides cleanly with no
  `flickering`, no leftover reserved space, and no click-through issues — **Option B is a go**.
  If any artifact appears, stop and switch to **Option A** (toggle-script) as the fallback.
- Acceptance: empty bar toggles correctly in/out of overview; no regressions; service restarts
  cleanly.

### Phase 1 — Port the easy (text/script) modules
- Port (reuse the existing scripts verbatim, just wrap in richer QML text widgets):
  `openrouter`, `firewall`, `sys_info`, `aurora`, `weather`, `peripheral-battery`, `notifications`.
- Implement `clock` in pure QML.
- Implement `tray` via built-in status notifier.
- Popup widgets for modules that had popups (openrouter, firewall, aurora, weather, notifications).
- Acceptance: identical info, identical placement, popups interactive.

### Phase 2 — Storage + battery text→selector (medium)
- `storage`: reuse open/eject scripts; render as list with per-device **Eject** buttons.
- `battery`: reuse details + profile scripts; render power-profile as **radio selector**
  (`low-power` / `balanced` / `performance`).

### Phase 3 — Interactive modules (the payoff)
- `volume`: use Quickshell **PipeWire** service for a real slider; keep backward-compat
  with the existing `_volume-ctl` cache/notify flow where beneficial.
- `display`: brightness slider (back to existing `brightness-ctl`/scripts); rotation,
  resolution/refresh list; toggles for ABM + stay-on + redlight (reuse existing toggle scripts).
- `bluetooth`: QML device list querying **bluez D-Bus / `bluetoothctl`** with connect/pair/
  disconnect. No third-party widget (locked decision 3).
- `wifi`: **the flagship interactive** — poll `nmcli -t`/D-Bus for network list, show SSID +
  signal/secure icons, per-network **Connect** with **inline password prompt**, disconnect,
  toggle enable/disable. This is the most custom work; hand-rolled as discussed since
  Quickshell network support is brand-new/unreleased.

### Phase 4 — Cutover: remove ironbar
- Once all modules render identically + interactively, switch the service default.
- Remove:
  - `home-manager/nixos/ironbar/` (or archive to `docs/` for reference)
  - ironbar import in `frank.nix`
  - `systemd.user.services.ironbar`, `toggle-ironbar.py`, related cleanup
  - ironbar `home.packages`, tray `has-tray-items` only if superseded
- Keep the Niri `startup.nix` `volume-ctl init` (still feeds volume UI) or fold into quickshell.
- Update `docs/ironbar-niri-overview.md` → new `docs/quickshell-niri-overview.md`.
- Update `docs/quickshell-migration-plan.md` status to **Done**.
- `statix check .`, `nix fmt`, `git` commit.

### Phase 5 — Harden (post-switch)
- Handle monitor hotplug / suspend-resume (mirror the self-healing in ironbar toggle script).
- Overview-mode behavior: the bar stays **overview-only** (locked decision 1).
  **Option B (native `n.overview.isOpen` binding) is primary**; if any show/hide artifacts
  appear over time (e.g., after monitor hotplug/suspend-resume), fall back to **Option A**
  (toggle-script) and note the reason.
- WiFi: confirm inline password prompt + `nmcli` connect flows work end-to-end.
- Bluetooth: confirm bluez D-Bus/`bluetoothctl` list + connect/pair flows.
- Battery/peripheral volatility check with Stylix/Catppuccin dark/light theme switching.

## Key Risks & Mitigations

| Risk | Mitigation |
|---|---|
| WiFi connect UI is the most custom bit | Phase-built standalone; reuse `nmcli`; D-Bus helper pattern |
| Quickshell NetworkManager support unreleased/brand-new | Hand-roll wifi panel; upgrade when stable |
| Noctalia/other finished shells archived/forked | Use **stock** quickshell 0.3.0 + own QML |
| QML learning curve vs JSON | Start with text/script ports, then one interactive |
| Ironbar currently also provides bluetooth (keep?) | Build `bluetooth.qml` from scratch — do not depend on a 3rd-party (decision 3) |
| Scripts depend on injected binaries via `lib.makeBinPath` | Recreate equivalent PATH in Quickshell wrapper |
| Systemd: stale processes after rebuild | `ExecStartPre=-pkill -f quickshell` (mirror ironbar pattern) |
| Option B: toggling layer surface via `visible` may show artifacts | Phase 0 decision gate → fall back to **Option A**; see Overview-Only section |

## Rollout & Verification

- Every phase ends with:
  - Service: `systemctl --user restart quickshell`; `journalctl --user -u quickshell`
  - `statix check .` (Nix for the module)
  - Manual visual check of bar placement/info.
- Full switch (Phase 4) gated on **Phase 3 interactive modules working** for wifi, display,
  volume, bluetooth, battery.

## Open Questions for User

All resolved via **locked decisions 1–4** and the **Option B primary / A fallback** choice.

- **Decision 5 (locked in this revision):** start with **Option B** (native `n.overview.isOpen`
  binding); fall back to **Option A** (toggle-script) only if the Phase 0 gate shows surface-toggle
  artifacts. No further input needed to begin.

---

_This file is the canonical plan for the Quickshell migration. Update status per phase as you go._