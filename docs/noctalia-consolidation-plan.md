# Noctalia V5 consolidation: research and implementation plan

Status: **Phases A–D and E0–E2 accepted; E3 Ghostty accepted, GTK checkpoint committed with Files/GTK3 follow-up deferred, Qt palette propagation verified; Vicinae next.**

Baseline: `cd2c817` (`Update: replace Ironbar with native Noctalia V5 on Niri`).
Research targets the pinned **Noctalia 5.3.0**, source commit
`a33122c4208a385e19c9a252e65e2751b2c44fbb`, not the old QML/Quickshell release.
Public documentation can change; validate against the pinned binary/source when implementing.

## Agreed scope

- Native Noctalia features first; compatible third-party plugins second.
- Restore peripheral battery visibility, removable-storage controls and stay-on/lid behavior.
- Test changes **one at a time**, with a separate commit after each accepted change.
- Make Noctalia the runtime theme controller, preferably retiring Darkman and runtime
  dependence on Stylix-generated colors as app integrations are migrated.
- Review custom battery notifications; do not duplicate Noctalia's notification daemon.
- OpenRouter and firewall summary are no longer migration requirements. Leave the actual
  NixOS firewall and its security policy untouched.
- No memory benchmark or Go rewrite. Aurora and other domain-specific widgets are deferred,
  not reasons to keep the old custom shell active.
- Preserve Niri, overview-only bar visibility, the current pill layout, launcher keybinds,
  working audio, tuned profiles, authentication and screen-lock safety.

## 1. Baseline snapshot before consolidation

Read-only service checks at research time found (later phase progress supersedes this snapshot):

| Component | Current owner/state |
|---|---|
| Shell + notification daemon/history | Noctalia active; dunst inactive |
| Battery warning producer | Custom `battery-notifications.service`, active |
| Automatic audio-based inhibition | Custom `audio-idle-inhibit.service`, active |
| Lock, monitor-off, idle suspend | swayidle + swaylock, active |
| Day/night scheduling + app theme propagation | Darkman, active; HM Stylix specialisations |
| Removable-device automount + notifications | Standard udiskie daemon; no tray icon |
| Noctalia battery warnings | Disabled (`battery.warning_threshold = 0`) |
| Noctalia wallpaper/idle/lockscreen/nightlight | Disabled to avoid competing owners |

The current idle sequence is lock at 300 seconds, monitor off at 305, then
`safe-suspend` at 310. Noctalia's idle/lockscreen features must remain disabled until
there is a separately tested reason to replace that chain.

## 2. Research findings

### 2.1 Peripheral batteries: built in, no plugin required

Noctalia's Control Center **Power → Connected Devices** shows peripheral batteries.
The Bluetooth service reads BlueZ Battery1 and has a UPower fallback; its device
cards can display battery percentages. Device reporting is the prerequisite: no
shell can invent charge data that the hardware/backend does not expose. [S1, S2]

For a permanent bar percentage, add another **built-in `battery` widget** with an
explicit UPower selector (object path, native path, model, serial or vendor).
`device = "auto"` intentionally selects only the system battery; it does not
aggregate mice/keyboards. Missing/not-present selected batteries hide themselves. [S3]

**Recommendation:** inspect native Bluetooth/Power cards with actual devices first.
Only add explicit peripheral battery pills if those cards are insufficient. Do not
write a battery polling script or install a battery plugin unnecessarily.

### 2.2 Removable storage: a specific V5 plugin fits

Candidate: **Udiskie Manager**, ID `aristides/udiskie`. [S4]

Reviewed community repository revision:
`bd834815ee5da2ed744a9cbf1425342a4eecba6f`.

- Luau manifest (`plugin.toml`), `plugin_api = 9`.
- Bar entry `aristides/udiskie:status`, panel `aristides/udiskie:manager`, service entry.
- Device/partition list, usage, open, mount/unmount, eject and detach/power-off controls.
- `hide_when_empty`, device count and optional event notifications.
- Spawns `udisksctl monitor` and uses udiskie CLI tools, `df` and `xdg-open`.
- Requires `udiskie`, UDisks2 CLI and file-opening tools on the **Noctalia service PATH**.
  On NixOS these are packages such as `pkgs.udiskie`, `pkgs.udisks`, `pkgs.xdg-utils`
  and the other CLI dependencies actually referenced by the reviewed scripts.

**Important:** the README proposes eliminating the udiskie daemon, but the reviewed
service monitors/list-refreshes devices and exposes mount commands; it does not
reproduce our configured `services.udiskie.automount = true` behavior on insertion.
Keep the standard udiskie automounter initially (and permanently if that remains
the simplest correct backend). Avoid duplicate notifications: retain udiskie's
notifications and set the plugin's `enable_notifications = false` for the first trial.

### 2.3 Stay-on, sleep inhibition and lid inhibition are different

| Mechanism | Actual behavior |
|---|---|
| Old manual `toggle-stay-on.sh` | `systemd-inhibit --what=idle`; not a lid/sleep blocker |
| Current automatic audio service | `--what=idle:sleep --mode=block` while its audio heuristic says playing |
| Native Noctalia Caffeine | In pinned V5.3.0, prefers a logind **idle** block; falls back to Wayland idle inhibition |
| Lid Guard plugin | Low-level logind `handle-lid-switch` block only |
| Original `safe-suspend` helper | Parsed inhibitor text and could reject explicit suspend for lid-only locks; structured replacement prepared in C2 |

The public Caffeine page describes Wayland idle inhibition; the **pinned source**
adds logind idle inhibition and prefers that when available. It never requests a
`handle-lid-switch` or high-level `sleep` block for Caffeine. Its separate
lock-before-sleep **delay** inhibitor is not an indefinite stay-awake lock. [S5, S6]

The system logind policy is currently:

```ini
HandleLidSwitch=suspend
HandleLidSwitchExternalPower=suspend
HandleLidSwitchDocked=ignore
```

`LidSwitchIgnoreInhibited` is not overridden. systemd defaults it to **yes**, so
high-level sleep/idle inhibitors do not by themselves guarantee that closing an
undocked lid will be ignored. Low-level `handle-lid-switch` locks are always
honored. Docked/multiple-display cases already ignore the lid through the configured
policy, independently of Caffeine. This can explain apparent old lid protection. [S7]

**Useful existing plugin:** **Lid Guard**, ID `8bury/lid-guard`, `plugin_api = 3`,
reviewed at the community revision above. It creates a transient user unit:

```text
noctalia-lid-guard.service
systemd-inhibit --what=handle-lid-switch --mode=block sleep infinity
```

It supplies a bar widget and Control Center shortcut, without editing logind.conf.
It does **not** prevent idle-daemon or explicit suspend. Its unit can outlive a
Noctalia restart or plugin disable; stopping the transient unit is the explicit
rollback. It ends when the user service manager stops. [S8]

**Recommendation:** separate controls:

- **Caffeine** = prevent inactivity-driven locking/power-off/suspend, subject to
  testing with our current swayidle and hidden-overview bar.
- **Lid Guard** = ignore lid-close events.
- **Both** = proposed manual "keep working with the lid closed" mode.

Do not claim this combination has been tested yet. Keep the automatic audio service
until native/plugin automation actually covers its behavior; a manual toggle is
not an automatic audio detector. Preserve an intentional way to suspend manually.

The original `safe-suspend` needed an audit: it parsed human-formatted
`systemd-inhibit --list` columns using awk (names/reasons may contain spaces), and
also treated lid inhibition as a reason to reject explicit suspend. A lid-only lock
should not automatically become a global sleep veto. Phase C2 prepares a structured
logind `ListInhibitors` query: only high-level `sleep`/`block` entries veto the helper,
invalid/query-failure responses fail closed, and normal `systemctl suspend` leaves
logind authorization, delay/weak locks and race handling intact. No inhibitor-bypass
flag is used. Eleven mock-command tests cover the helper without suspending the host.

### 2.4 Notifications: the daemon is already consolidated

Noctalia already owns `org.freedesktop.Notifications`, toasts and history. Dunst is
not running. The remaining custom notification **producer** is primarily the
battery warning service (20%, 5%, fully charged), not a second notification daemon.

Native Noctalia battery warnings can replace most of it: configure a 20% warning,
with built-in critical escalation at 5% and 2%. Native warnings are evaluated even
if the shell starts below the threshold. Peripheral warning thresholds are opt-in.
`warning_threshold = 0` disables all native warnings for that battery. [S9]

The old full-charge toast is not identical to the native low-battery feature. The
default proposal is to adopt native warnings; if a full-charge toast is still wanted,
use a small deduplicated battery-state hook, not a second persistent monitor. Native
hooks expose battery state/percentage, but hook events must be checked carefully:
`battery_plugged` also covers pending-charge and is not "100% reached" by itself. [S10]

### 2.5 Noctalia can control system appearance, not only its own colors

V5.3.0 supports: [S11–S13]

- `theme.mode = dark | light | auto` for app appearance/templates.
- `theme.shell_mode = follow` to keep the shell in the same mode.
- Sunrise/sunset scheduling using the existing configured location; Night Light
  does not need to be enabled for automatic theme scheduling.
- `theme.sync_color_scheme = true`: writes the GNOME light/dark preference used by
  the portal and supporting apps, without requiring any template.
- Built-in Catppuccin and other palettes, custom palettes and wallpaper-derived colors.
- Built-in, community and user app templates with reload hooks.
- `theme_mode_changed` / `colors_changed` hooks, with the resolved mode in
  `NOCTALIA_THEME_MODE` for the former.

The installed pinned binary lists built-in templates for Ghostty, GTK3/4, Qt,
KColorScheme, Niri, Emacs, Starship and others. Nushell and our custom Vicinae theme
need a specific integration/user template; do not assume a matching built-in exists.
Community templates are opt-in external code/config and need review like plugins.

**Key distinction:** Stylix is currently a **build-time theme generator**, while
Darkman is the runtime scheduler/controller applying its light/dark Home Manager
specialisations. Noctalia can replace Darkman as the controller without first
removing every Stylix target. The desired end state is Noctalia-owned runtime mode,
palette and app theme files; Nix continues to install/configure apps and fonts.

**NixOS boundary:** current Ghostty, GTK CSS, Qt5ct/Qt6ct, Niri and Vicinae theme
paths resolve to read-only Home Manager/store files. Do not just turn on all
Noctalia templates: some shipped apply hooks rewrite main configs; GTK's hook can
even replace a read-only symlink with a mutable local file. The next rebuild can
then fail or reverse the change. [S12, S14]

For each migrated app:

1. Keep its main config declarative with a fixed include/theme reference.
2. Render Noctalia's theme into a **separate writable file**.
3. Disable only conflicting Stylix/manual color output for that app.
4. Choose a template/apply hook that does not rewrite the main managed file.
5. Reload the app without rewriting application behavior/settings.

Examples: Ghostty's main config can select `theme = noctalia` once, with a writable
`themes/noctalia`; GTK CSS can declaratively import a writable `noctalia.css`.
Niri can include a generated color-only KDL file, after removing conflicting color
definitions and validating include/merge semantics. Do not let a template take over
Niri input, keybindings, tiling or monitor configuration.

## 3. Implementation sequence and acceptance gates

Every phase: make the smallest change, validate the generated Noctalia config,
build the Framework configuration, let the user test it, then commit. No phase is
accepted solely because Nix evaluates. Do not activate/rebuild with sudo as an agent.

### Phase A — Native peripheral battery visibility

Progress:
- Read-only inspection confirmed Noctalia is active and native Bluetooth IPC works.
- `noctalia msg bluetooth-status` reported `off`.
- UPower enumerated the internal `BAT1`, AC adapter and aggregate DisplayDevice;
  no peripheral battery was present at inspection time.
- Bluetooth was not enabled and no pairing/device state was changed by the agent.
- No plugin, guessed UPower selector or polling implementation was added.
- User connected headphones and confirmed that the native battery percentage is visible.
  The native view covers that use case; no additional battery configuration/plugin was added.
- Reconnect/resume and other peripheral types remain regression checks, not claims of
  completed hardware testing. Proceed with the storage trial as the next isolated change.

Changes:
- Inspect actual devices in Bluetooth and Power → Connected Devices while connected.
- If always-visible percentages are needed, add built-in battery widget instances
  with stable UPower selectors; prefer model/native identity over unstable hotplug paths.
- Do not install a battery plugin or restore the old polling module.

Gate: mouse/keyboard/headset batteries match the backend; disconnected devices
vanish; reconnect and suspend/resume refresh; no peripheral is mistaken for BAT0/BAT1.
If already adequate in the native panels, this phase is verification-only.

### Phase B — Storage plugin trial (one plugin only)

Implementation accepted:
- Added `noctalia/storage.nix` and a pinned, non-flake community source at
  `bd834815ee5da2ed744a9cbf1425342a4eecba6f`; only the udiskie plugin is exported.
- Configured `aristides/udiskie`, a storage pill after the app tray, hide-when-empty,
  device count, no duplicate event notifications and no automatic file-manager opening.
- Existing udiskie automount/notifications remain enabled. The service gets an explicit
  tool PATH. Mutable community source is disabled to prevent duplicate plugin IDs;
  official source stays available and auto-updates remain off.
- Noctalia config validation, plugin lint (0 errors/warnings), upstream translation tests,
  overview tests, targeted statix and the full Framework build passed.
- Read-only device enumeration succeeded with the plugin's requested udiskie fields.
- User activated the configuration, tested the storage integration and reported it works.
  Treat the basic live trial as accepted; encrypted-media, busy-device and multi-partition
  edge cases are not individually confirmed. No storage operations were performed by the agent.
- No Caffeine/Lid Guard, notification or theme ownership changes were made in this phase.

Changes:
- Review/pin the exact `aristides/udiskie` version/source and compatible API; expose
  required commands on Noctalia's service PATH.
- Enable only that plugin; add `aristides/udiskie:status` near tray/storage area.
- Set `hide_when_empty = true`, show count, no automatic file-manager launch.
- Keep the existing udiskie automounter and its notifications; disable plugin
  event notifications to avoid duplicates.
- After a GUI trial, capture accepted settings/source declaratively. Avoid duplicate
  plugin IDs from mutable upstream sources and pinned local/path sources. Keep
  automatic plugin updates off; pin reviewed code rather than silently following main.

Gate: insert USB/SD, automatic mount still works, open in file manager, unmount,
eject/power-off, reinsertion, no duplicate notifications, busy-device error, and
multi-partition handling. Test encrypted media only with disposable/test data.
No bulk unmount/eject against real work drives during agent tests.

Rollback: disable plugin/remove widget; keep udiskie enabled. Do not change logind
or theme ownership in this phase.

### Phase C — Native Caffeine, then Lid Guard (separate substeps)

C1 accepted:
- Added the built-in `caffeine` bar widget between brightness and battery. It uses
  Noctalia's existing native inhibitor; there is no new plugin or helper process.
- Caffeine is not enabled automatically. Existing swayidle/swaylock, audio inhibition,
  global lid policy and `safe-suspend` remain unchanged.
- User confirmed the Noctalia `idle`/`block` inhibitor appeared after enabling Caffeine
  and subsequently confirmed the laptop-idle test works. The native Caffeine trial
  is accepted. Release/off behavior remains a regression check; lid-close protection
  and manual suspend are separate capabilities, not proven by this test.
- Generated Noctalia config validation, overview tests, targeted statix and the full
  Framework build passed. The agent did not activate the config or toggle Caffeine.
- Lid Guard is not enabled in C1. Do not combine that change with the native trial.

C1: test existing native Caffeine first. Optionally add the native `caffeine` pill.
Inspect actual inhibitors and logs, then verify lock/monitor/suspend timers with
Caffeine on/off **outside overview** as well as while the bar is visible. Check
whether logind-only Caffeine inhibits our swayidle path; do not infer that from a
coffee icon. Keep existing swayidle/swaylock and audio inhibition throughout.

C2 implementation accepted:
- Curated plugin source/CLI dependencies now live in `noctalia/plugins.nix`; storage
  behavior remains in `storage.nix`. Added reviewed `8bury/lid-guard` from the same
  pinned community revision as storage, not a new unpinned source.
- Added a `lid-guard` shield pill beside Caffeine. It does not acquire an inhibitor
  on plugin load; the user must toggle it on. Global logind policy is unchanged.
- Replaced the inline awk helper with `niri/safe-suspend.sh`: structured busctl JSON,
  exact sleep-token matching, preserved sleep blocks and normal logind delay behavior,
  fail-closed query/parse failures. Idle/lid-only locks do not veto manual suspend.
- Added `checks.x86_64-linux.safe-suspend`, with 11 tests using fake service commands.
- Both native plugin lints, translation tests, Noctalia config validation, overview
  tests, shellcheck, targeted statix and full Framework build passed.
- User tested the Lid Guard trial and reported it works. Basic live acceptance is
  recorded; each AC/battery, docked/undocked, manual-suspend and off/release edge case
  is not individually confirmed. Keep these in the regression checklist.
- The agent did not activate the config, toggle Lid Guard or request any suspend.

C2: audit `safe-suspend` and document which actions should remain possible while
lid-only inhibition is active. Review/pin **only** `8bury/lid-guard`, provide its
systemd/coreutils commands and add its shortcut/widget. Do not change global
`HandleLidSwitch` policy simply to make the plugin appear functional.

C3: test the combination. Expected behavior to validate:

| Mode | Idle expiry | Undocked lid close | Manual suspend |
|---|---|---|---|
| Both off | Existing 300/305/310-second chain | Suspend per current policy | Available unless another sleep blocker exists |
| Caffeine only | No inactivity action if integration works | Still governed by lid policy | Not globally blocked by Caffeine alone |
| Lid Guard only | Idle actions remain possible | Ignored | Should remain possible after helper audit |
| Both on | No inactivity action | Ignored | Deliberately preserved/clearly documented |

Repeat AC/battery, docked/undocked and audio playing/stopped. A docked lid-close
success alone proves nothing because our docked policy already ignores the lid.
Perform lid tests manually with the machine ventilated, data saved and no risk of
leaving an awake laptop in a bag. Do not automate suspend/lock during research.

Rollback: turn Caffeine off, disable plugin and explicitly run
`systemctl --user stop noctalia-lid-guard.service`; confirm normal lid behavior.
Keep the existing audio service unless a separate automatic replacement passes tests.

### Phase D — Replace the custom battery-warning producer

Implementation accepted:
- Set Noctalia's native system-battery warning threshold to 20; its built-in critical
  5% and persistent 2% warning escalation remains unchanged.
- Removed the `./battery-notifications` Home Manager import in the same change. The
  legacy files stay for rollback, but the service is absent from the evaluated config.
- Noctalia remains the only notification daemon; no full-charge hook or replacement
  polling script was added. The old full-charge toast is not retained by default.
- Read-only inspection found no GUI battery/notification-daemon override masking this.
- Config evaluation confirmed threshold=20, native daemon=true, custom monitor=false.
  Native config validation, overview/safe-suspend tests and full Framework build passed.
- User activated the configuration. Read-only systemctl checks confirmed Noctalia
  active/running, the legacy monitor not-found/inactive, and the installed threshold 20.
- User accepted committing this implementation and will report any warning issues
  during normal use. Actual low-charge escalation is not claimed as tested.
- Agent did not manipulate battery data or force a discharge; do not drain to 2% to test this.

Changes:
- Enable Noctalia's native battery warning threshold at 20.
- In the **same change**, stop/remove the custom battery-notifications import/service
  so only one producer owns low-battery warnings.
- Adopt native 20%/5%/2% warnings. Full-charge toast is optional and is not a blocker;
  if requested, implement a small tested hook with deduplication.

Gate: notification history, urgency/DND behavior and charge-state handling remain
correct; no duplicated warnings. Use controlled/mock tests or natural battery cycles;
do not intentionally discharge the laptop to 2% just to test a notification.
Rollback restores the old service and sets Noctalia warnings back to zero.

### Phase E — Noctalia becomes the runtime theme controller

Do this after the small widget/plugin trials, not in the same rebuild.

**E0: palette warning checkpoint (accepted).**
- Runtime logs exposed that the generated custom `Stylix` palette was invalid despite
  the JSON file existing. The pinned runtime loader requires a `terminal` object in
  each mode; our custom mapping only supplied UI roles. Basic config validation did
  not catch that runtime-palette requirement.
- Switched Noctalia to its shipped `Catppuccin` palette (Mocha/Latte), removed the
  custom mapping and managed `Stylix.json`. No GUI theme overrides masked this change.
- Kept `theme.mode = config.stylix.polarity` for this isolated fix; Darkman scheduling,
  HM specialisations, wallpaper handling and all app theme files remain unchanged.
- Evaluation confirms source=builtin, builtin=Catppuccin, no managed custom palette.
  Noctalia config validation, overview/safe-suspend checks, targeted statix and the full
  Framework build pass. User rebuilt; current-process logs contained no palette/theme
  warning, the old managed JSON was absent, and the user confirmed the appearance is right.

**E1/E2 implementation accepted (activated/tested by the user).**
- Backed up Noctalia GUI settings to `~/.local/state/noctalia/settings.pre-theme-controller.toml`;
  read-only inspection found no existing theme/hook overrides to reconcile.
- Set Noctalia `theme.mode = auto`, `shell_mode = follow`, `sync_color_scheme = true`,
  independent of `config.stylix.polarity`. Built-in Catppuccin remains the palette.
- Removed both the system-profile Darkman import and HM Darkman import. Old scripts
  remain inactive for rollback. Normal HM activation stops a still-running legacy daemon.
- Added a temporary one-way adapter in `noctalia/theme.nix` + `theme_bridge.py`.
  Hooks/startup/rebuild/hotplug requests are atomic files; a systemd PathExists/oneshot
  pair drains/coalesces them, with no persistent polling daemon or Nix rebuild.
- The worker queries Noctalia's resolved mode, applies the unique prebuilt HM
  specialisation from `/run/current-system`, refreshes SwayOSD/Vicinae, selects the
  existing Nushell NUON, and refreshes awww. It never writes a mode back to Noctalia,
  writes the portal preference directly, or restarts Noctalia. It can request native
  `templates-apply` so Noctalia reasserts its own preference after activation cleanup.
- A shared lock serializes ordinary HM linking and compatibility activations. The
  worker waits for normal system HM activation before locking; its own child skips
  request/lock hooks to avoid recursive activation and deadlocks. New events survive
  processing; failed work leaves a pending request for retry.
- Wallpaper hotplug now requests a refresh using Noctalia's mode, not `darkman get`.
- Tests cover 14 bridge cases with all commands mocked (plus 4 overview and 11 safe-suspend
  tests). A flake invariant check enforces identical Noctalia config/service and bridge
  service across base/dark/light generations, absence of the legacy controller and
  absence of any HM-managed GNOME color-scheme key.
- Compatibility limitation: this syncs existing Catppuccin dark/light app themes, not
  arbitrary Noctalia palettes in every app. Per-app templates in E3 remove that limit.
- User's first rebuild passed startup checks: native mode light, app bridge completed,
  path unit waiting, worker successful/idle, no pending request, Darkman not-found/inactive,
  Nushell matched light. Startup/rebuild requests were drained without an ongoing loop.
- That check exposed one ownership conflict: Stylix's GNOME target reapplied `default`
  for light mode after Noctalia's preference write. The follow-up disables only that
  target, explicitly preserves its app fonts and requests Noctalia's native preference
  resync after compatibility activation. After the follow-up rebuild, the resolved light
  mode matched `prefer-light` and the bridge completed successfully without pending work.
- User confirmed dark/light switching works. The Noctalia PID remained 243684 before
  and after that trial; worker result was success and the final app/system mode matched light.
- Native config validation, bridge/overview/suspend checks, theme invariants, shellcheck,
  targeted statix and full Framework build pass. Basic runtime handover is accepted;
  automatic schedule boundaries, hotplug and suspend/resume remain regression checks.

**E1: inventory and prepare ownership.**
- Inventory actual Stylix and manual color outputs, reload paths and store symlinks.
- Decide which clients only need light/dark mode and which need generated colors.
- Back up Noctalia GUI overrides before reconciling relevant keys; do not delete its
  whole settings state. Preserve the chosen bar, devices, plugins and location.
- Initially keep Catppuccin Mocha/Latte; no palette redesign is needed for this work.

**E2: reverse control safely, with a temporary compatibility bridge if needed.**
- Make Noctalia's mode independent of `config.stylix.polarity`; configure manual/auto
  mode through Noctalia, `shell_mode = follow`, `sync_color_scheme = true`.
- Retire the **system-level** Darkman user service in `modules/services/darkman.nix`
  (and its import as appropriate), not just the HM scripts.
- Remove Darkman's HM activation callbacks/light-mode.d/dark-mode.d ownership so
  rebuilds cannot unexpectedly reapply a different mode.
- To preserve unmigrated apps temporarily, a small `theme_mode_changed` bridge can
  apply the prebuilt HM light/dark specialisation using the resolved hook variable.
  This bridge is compatibility-only, not the final theming architecture.
- Do **not** reuse `darkman-switch-mode.sh` unchanged: remove its Noctalia restart,
  reverse color-scheme writes and Darkman queries. Otherwise theme events can loop.
- Serialize/idempotently coalesce mode applications, handle activation-in-progress,
  and test startup/rebuild reapplication. Switching modes must not rebuild Nix.
- Keep Noctalia's own generated config/palette identical across compatibility
  specialisations so applying one does not restart the shell and recursively emit hooks.

**E3: migrate writable app-theme outputs one target per commit.**

Ghostty implementation accepted:
- Main Ghostty config declaratively selects `theme = noctalia`; Shift+Enter binding
  is unchanged. Removed our custom color generator and static Stylix light/dark files.
- `noctalia/ghostty.nix` enables only the built-in `ghostty` template. The shipped
  apply hook recognizes that fixed reference, skips editing the managed config,
  and uses the shipped reload implementation. No community/custom template is used.
- A small activation-only preparer handles legacy read-only output: back up once to
  the Noctalia state directory, replace only the user-facing theme file with a private
  writable copy, never chmod/truncate a symlink/hardlink target. New installs get a
  comment-only placeholder until the native template renders. No persistent process.
- The preparer runs after writeBoundary/before linkGeneration. Existing writable
  generated colors are left untouched during later compatibility activations.
- Native service PATH explicitly includes the built-in apply/reload hook's CLI tools.
- 10 tests cover output preparation, backup/idempotence, protected link targets,
  rendering the pinned stock template in both modes, and the pinned apply hook preserving
  a read-only main-config symlink. The reload script is mocked, so tests never signal
  a real Ghostty process. The common Noctalia check now runs 28 tests total.
- Flake invariants enforce the fixed theme selection, enabled built-in template,
  and absence of managed runtime/static Ghostty theme outputs across all variants.
- Config validation and full Framework build pass. User rebuilt and confirmed that
  changing Noctalia's palette now changes Ghostty too. Dark/light mode switching
  already worked before; the newly accepted behavior is arbitrary palette propagation.
- Read-only deployment checks confirmed the main config remains a Nix-managed symlink,
  the runtime theme is a private writable regular file (0644, one link), the original
  backup is private (0600), and both old static Stylix theme links are gone.
- No recent Ghostty/template permission errors were found. Individual keybindings
  were preserved in code but not separately claimed as live-tested.

GTK3/GTK4 checkpoint approved for commit (partial visual acceptance):
- `noctalia/gtk.nix` enables the pinned built-in `gtk3` and `gtk4` templates alongside
  Ghostty. Both `gtk.css` entrypoints declaratively contain only the literal
  `@import url("noctalia.css");`, so the upstream apply hook skips rewriting them.
- Separate `noctalia.css` outputs remain writable. The shared activation-only preparer
  seeds both with valid CSS comments before linkGeneration and safely privatizes old
  protected outputs if needed. Existing runtime colors are not replaced on activation.
  The preparer was renamed to `prepare_theme_output.py`; Ghostty behavior is unchanged.
- Disabled the Stylix GTK target's fixed CSS and removed the competing managed
  `gtk-theme` preference. Kept Noto Sans 11, Papirus, Quintom_Snow/24 and the adw-gtk3
  package. The upstream GTK hook selects adw-gtk3/adw-gtk3-dark through gsettings or
  dconf; Noctalia still owns color-scheme preference through its existing native path.
- Removing that Stylix target also removes its flattened `~/.themes/adw-gtk3` and
  Flatpak override pin. This stage covers native GTK apps; Flatpak-specific palette
  access/theming needs a separate review rather than retaining an obsolete fixed palette.
- Six tests cover both read-only import symlinks, gsettings and dconf paths, missing
  output handling, valid placeholders, idempotence and actual stock template rendering
  for two distinct palettes in both modes. Settings calls are mocked, never live.
  The common Noctalia check now runs 34 tests. Flake invariants also enforce preserved
  assets, import ownership, enabled template IDs and absence of a managed gtk-theme key.
- Native config validation, tests/invariants, statix and full Framework build pass.
  User rebuild and native GTK3/GTK4 palette/mode/font/icon/cursor checks remain pending.
  Some GTK apps may require reopening to pick up CSS; do not promise universal live reload.
- First GTK rebuild exposed an overview-watcher lifecycle gap: the watcher stopped,
  Noctalia's restart was cancelled, and its started hook never ran. Manually starting
  only the watcher restored its subscription. Added graphical-session enablement and
  idempotent post-reloadSystemd start, with invariants across all variants. Permanent
  lifecycle fix awaits rebuild; GTK visual acceptance remains pending.
- User reported no live palette update in Files and Adwaita Bluetooth. Both are
  GTK4/libadwaita apps, not a GTK3/GTK4 pair. Both processes predate the latest CSS
  render; Files also predates the migration. Runtime outputs contain the selected
  palette and the actual apps' GTK 4.22.4 library parses the managed import plus
  generated CSS without diagnostics. GTK4 loads user CSS at initialization; the
  stock hook does not provide generic live user-CSS reload. A full quit/relaunch
  after choosing a different palette was the next diagnostic gate. User then confirmed
  Adwaita Bluetooth adopts the palette after restart, but Files still does not. Neither
  process was running at the next inspection, so a fresh Files launch/environment must
  be inspected before attributing its behavior to caching. GTK3 remains untested.
- User explicitly approved committing this checkpoint and moving on. Adwaita Bluetooth
  startup palette propagation is confirmed; Files behavior, GTK3, and full visual
  acceptance remain deferred rather than being marked as successful. The overview
  lifecycle fix is included; its rebuild recovery still needs observation.
- Keep template enablement declarative. Upstream undo hooks try to edit gtk.css and are
  not the rollback path for Nix-managed imports; revert the Nix change/rebuild instead.

Qt implementation deployed, runtime consumption verified:
- `noctalia/qt.nix` enables the pinned built-in `qt` template, which writes the two
  `qt5ct/colors/noctalia.conf` and `qt6ct/colors/noctalia.conf` palettes. There is no
  custom color generator, main-config apply hook or new background service.
- Moved the Qt main configs out of `vicinae.nix` into that module. Both remain
  declarative, select custom_palette and the corresponding runtime color path, and
  retain Papirus, Noto Sans 11 and JetBrainsMono Nerd Font 11.
- Changed style from Kvantum to Fusion so the generated QPalette is honored.
  System Qt still owns plugin installation/environment. Qt6ct's plugin advertises
  both qt6ct and qt5ct; real offscreen tests confirm the existing qt5ct setting works
  for both Qt versions. No environment change/session restart is required.
- The existing output preparer backs up and detaches old protected palette files
  before linkGeneration, never modifies link targets, and preserves writable output
  on later app-theme activations. New installs get a valid INI header until rendering.
- Four Qt tests cover actual stock palette role counts, bootstrap, protected legacy
  files, and real Qt5/Qt6 application consumption for two distinct palettes in both
  modes. Offscreen C++ probes verify colors, Fusion, font families, Papirus, the
  platform alias and preserved read-only main-config symlinks. No user GUI is launched
  or live preference changed. The common Noctalia check now runs 38 tests.
- Native config validation, formatting/statix, invariants and full Framework build
  pass. User activation and offscreen runtime consumption are verified below;
  app-specific visual tests remain pending. Do not assume
  live reload: the stock Qt template has no reload hook; some apps may need restart
  or ignore system palettes entirely.
- User rebuilt with substitutions disabled. Deployment inspection confirmed both
  managed main-config symlinks, writable runtime palettes and private legacy backups.
  Real offscreen Qt 5.15.19 and Qt 6.11.1 probes against the live files match the
  generated window/foreground/highlight roles and confirm Fusion, both expected font
  families and Papirus. Main configs remained unchanged. Overview watcher is active
  after the rebuild; the compatibility worker completed successfully.
- User selected Kanagawa while staying in light mode. Both live Qt5/Qt6 probes
  picked up the new palette: window #eff1f5 -> #f2ecbc, foreground #4c4f69 -> #545464,
  highlight #d5c0f2 -> #c7d6b3. Fonts, Papirus, Fusion and managed main config symlinks
  remained intact; Noctalia and the overview watcher stayed active. Runtime palette
  propagation is verified independently of a dark/light change. Already-running
  GUI app reload and app-specific visual behavior remain unverified.
- Vicinae is deliberately unchanged: it has its own generated Stylix theme and needs
  a separately reviewed integration after Qt is accepted.

| Target | Proposed integration / caution |
|---|---|
| Ghostty | Declarative `theme = noctalia`; writable theme file; test reload hook and avoid main-config writes |
| GTK3/GTK4 | Declarative CSS import + writable generated CSS; package needed GTK theme; ensure apply hooks do not detach HM symlinks |
| Qt/Vicinae | Preserve fonts/Papirus/Qt platform integration; use writable color/theme files and a reviewed reload path; Vicinae is a user-template candidate |
| Niri | Declarative include of writable colors only; remove conflicting Nix colors; validate Niri before reload |
| Nushell | Keep current runtime theme-reader hook; generate NUON or initially select existing dark/light NUON from Noctalia mode hook |
| Zed/editors/Emacs | Audit existing Stylix output and read-only configs; use system appearance or opt-in templates without replacing editor configuration |
| Zen/other apps | Prefer system color-scheme/media queries first; review external templates only if still needed |
| swaylock/SwayOSD | Preserve authentication/OSD behavior; change colors only through a separately tested file/reload integration |

Disable a Stylix target/manual color generator **when** its replacement is tested,
not globally at the start. Pin/review template sources and their hooks. Built-in
assets from the pinned Noctalia package are preferred to mutable remote templates.

**E4: wallpaper and hotplug ownership.**
- Either move wallpaper/backdrop handling to native Noctalia in a separate tested
  substep, or retain awww with a small Noctalia-driven wallpaper/hotplug adapter.
- Rewrite `monitor-hotplug.sh`'s `darkman get` dependency before removing Darkman;
  otherwise it falls back to dark wallpapers after monitor changes.
- Preserve current light/dark wallpaper selection, overview backdrop placement and
  hotplug behavior. Do not run two wallpaper owners on the same layer/output.

Gate for each substep: Noctalia toggle/auto schedule changes shell and relevant
apps, system color-scheme/portal follows, open terminals update, no read-only-file
errors, no activation/restart loops, no changed Niri behavior, and selection survives
logout/login/rebuild/suspend. GUI mode switches should not require a rebuild.

### Phase F — Remove temporary and inactive layers

Only after the corresponding replacements pass their gates:

- Delete old Ironbar/Quickshell code and unused quickshell/qml-niri inputs/lock nodes.
- Delete old dunst and battery-monitor configuration once no active references remain.
- Remove Darkman package/service/scripts and its wallpaper queries/activation hooks.
- Remove the temporary HM-specialisation theme bridge once runtime templates/system
  appearance cover all required clients; remove no-longer-needed light/dark HM
  specialisations after checking remaining consumers.
- Reduce or remove NixOS-home Stylix color targets once all consumers are migrated;
  retaining it for fonts/cursor/static defaults is valid. Do not remove global Stylix
  inputs/shared theme files while other hosts/configs still depend on them.
- Keep Framework pw-loopback init, audio keep-alive, tuned, screen locking and any
  necessary automatic audio/lid safeguards; these are not shell-widget leftovers.
- Keep the small overview bridge unless Noctalia gains an equivalent strict native
  overview-only mode. Smart auto-hide is not equivalent.
- Do not expand this work into replacing Vicinae, the lockscreen, polkit, or every
  system service just because Noctalia can implement some of them.

## 4. Testing/commit discipline

For each accepted functional change:

1. Run pinned Noctalia config validation and overview-bridge tests.
2. Validate plugin API compatibility and run the candidate plugin's tests where provided.
3. Build the full Framework system; format/lint changed Nix/scripts.
4. User activates and exercises that phase's manual acceptance cases.
5. Record observed behavior and commit one logical step. Keep a reversible prior commit.

Research alone does not count as live proof for Caffeine/lid semantics, plugin
behavior or application reloads. No plugins, battery thresholds, theme settings,
service ownership or power policy were changed as part of this research.

## 5. Recommended immediate next action

Start with **Phase A**: inspect native connected-device battery reporting and add
explicit built-in battery pills only if wanted. Then trial the **storage plugin**,
then **Caffeine/Lid Guard**, then native battery alerts. Theme-controller migration
is the larger follow-up and should stay separate from these smaller changes.

## Sources

Pinned source was checked where user-facing docs were incomplete.

- **S1:** https://docs.noctalia.dev/noctalia/control-center/ (Power connected devices, Bluetooth)
- **S2:** https://github.com/noctalia-dev/noctalia/blob/v5.3.0/src/dbus/bluetooth/bluetooth_service.cpp
- **S3:** https://docs.noctalia.dev/noctalia/bar/widgets/battery/
- **S4:** https://github.com/noctalia-dev/community-plugins/tree/bd834815ee5da2ed744a9cbf1425342a4eecba6f/udiskie
- **S5:** https://docs.noctalia.dev/noctalia/bar/widgets/caffeine/
- **S6:** https://github.com/noctalia-dev/noctalia/blob/v5.3.0/src/idle/idle_inhibitor.cpp
  and https://github.com/noctalia-dev/noctalia/blob/v5.3.0/src/dbus/logind/logind_service.cpp
- **S7:** https://freedesktop.org/software/systemd/man/latest/logind.conf.html
  and https://systemd.io/INHIBITOR_LOCKS/
- **S8:** https://github.com/noctalia-dev/community-plugins/tree/bd834815ee5da2ed744a9cbf1425342a4eecba6f/lid-guard
- **S9:** https://docs.noctalia.dev/noctalia/services/battery/
- **S10:** https://docs.noctalia.dev/noctalia/automation/hooks/
- **S11:** https://docs.noctalia.dev/noctalia/theming/
- **S12:** https://docs.noctalia.dev/noctalia/theming/app-theming/
- **S13:** https://docs.noctalia.dev/noctalia/theming/templates/
- **S14:** https://github.com/noctalia-dev/noctalia/tree/v5.3.0/assets/templates
- Plugins/compatibility: https://docs.noctalia.dev/noctalia/plugins/
- Native idle behavior: https://docs.noctalia.dev/noctalia/services/idle/
