# Noctalia V5 consolidation: research and implementation plan

Status: **Phases A–D and E0–E2 accepted; E3 Ghostty accepted, GTK checkpoint committed with Files/GTK3 follow-up deferred, Qt palette propagation verified; Requested app templates accepted, including fzf/Nushell; cache-trust revocation activated and verified; Niri and Nushell accepted; native wallpaper accepted; remaining-consumer audit completed initially, Starship accepted; native bottom-center OSD/control migration accepted; btop committed without live testing; plain Emacs committed without live testing; dormant-target/KDE-overlay cleanup committed without activation verification; Xresources committed without live testing; GTKSourceView committed without live testing; native lock-screen migration requested, password-PAM preflight accepted; manual native-lock password/fingerprint trial accepted; keyboard/lid sleep verified; native-idle replacement activated after automatic suspend launcher failure; automatic sleep/key-wake and Caffeine/audio acquisition-recognition-release verified, extended validation pending, with deferred GTK/bridge cleanup pending.**

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

Vicinae community-template implementation accepted:
- Pinned `noctalia-dev/community-templates` at
  `7aae018927ae35d007734868388c34c901870f45` as a non-flake input. Register only its
  reviewed `vicinae/vicinae.toml` and `apply.sh` via a declarative user template;
  no fork, mutable runtime download or custom color generator.
- `noctalia/vicinae.nix` selects `noctalia` for both light/dark modes with Papirus.
  The installed v0.23.0's theme-set handler rescans the database and reloads when
  that ID already matches the effective configured theme, without writing settings.
  Nix's existing high-priority VICINAE_OVERRIDES wrapper remains the config owner.
- Removed the custom Stylix color mapping/theme file, retaining launcher settings,
  extensions, keybindings, fonts and service integration. Removed Vicinae from the
  compatibility bridge restart list; only SwayOSD remains there.
- Prepare writable `~/.local/share/vicinae/themes/noctalia.toml` before linkGeneration,
  with safe legacy backup handling and built-in-theme inheritance until first render.
  Upstream apply.sh receives the pinned Noctalia SVG, installs it only if missing,
  and preserves any legacy icon. Explicit service PATH includes the Vicinae CLI.
- Six integration tests exercise upstream rendering, its unchanged hook with fake
  CLI, protected files/icon preservation, placeholders and idempotence. A test-only
  probe compiles the pinned Vicinae theme parser/resolver and checks both modes and
  two palettes without starting a server. One added bridge test forbids Vicinae
  restarts. Total Noctalia tests: 45, plus 11 safe-suspend tests.
- Invariants enforce the fixed selector and identical launcher settings/units across
  variants. Full Framework build and native config validation pass, with substitutions
  disabled. User rebuilt and confirmed palette integration works. Deployment checks
  confirmed a writable runtime theme, removed static Stylix output and active launcher,
  shell and overview watcher. PID stability across changes was not independently
  sampled, so do not claim that from parser/hook mocks alone.
- One initial post-hook invocation preceded Vicinae socket readiness and logged
  connection refused during the rebuild. The rendered file was present for launcher
  startup and subsequent user palette tests worked. Retain this as a known transient
  startup warning, not an error-free-startup claim or reason to add a restart daemon.

Zed community-template implementation accepted:
- `noctalia/zed.nix` consumes the same pinned community repository's `zed/zed.json`
  verbatim, registering only Zed's output, not the optional Gram entry. The upstream
  family contains both modes and four opaque/transparent variants; select the opaque
  `Noctalia Dark`/`Noctalia Light` variants with Zed's native `theme.mode = system`.
- Disabled the Stylix Zed target and removed its static Base16 theme. Preserved
  JetBrainsMono/Noto fonts and their existing 4/3 point conversion, tab-bar options,
  Nix extension/LSP setup and mutable settings merge behavior. Unrelated user settings,
  icon choice, language servers and extension selections remain untouched.
- Separate `zed/themes/noctalia.json` stays writable. The shared preparer seeds the
  two selected names with an empty-refinement family before linkGeneration, handles
  protected legacy output with a backup, and preserves existing writable output.
  No app-setting apply hook, custom color generator or restart service is added.
- Six tests render two palettes/all four variants in both default modes, verify the
  complete family is independent of the active mode, execute the actual generated
  Home Manager JSON5/settings merger in temporary dirs, and check settings preservation,
  bootstrap and protected output. Total Noctalia tests: 51, plus 11 safe-suspend tests.
- Invariants enforce stable settings across specialisations, font preservation,
  system-mode selectors and runtime-file ownership. Shared/Darwin modules are unchanged.
- Native config validation, lint, full Framework build and tests pass with substitutions
  disabled. User rebuilt and confirmed the integration works. Deployment inspection
  verified system-mode selectors, all four generated variants in a regular 0644 file,
  unchanged font families/sizes, removal of the old Stylix theme and active shell/
  overview watcher. GUI behavior is user-confirmed; JSON tests themselves do not
  establish full schema validation or independently instrument editor reload.

Zen Browser community-template implementation accepted:
- `noctalia/zen-browser.nix` consumes both pinned upstream CSS files verbatim.
  Register them without the community apply hook: it writes through protected CSS
  symlinks, scans obsolete/backup profiles, and rewrites user.js without backups.
- GUI template overrides were checked: no duplicate community Zen entry is active.
  Do not enable that mutable catalog entry alongside these hook-free registrations.
- Nix owns imports only in `.zen/default/chrome`. Rendered CSS lives in persistent
  XDG state rather than upstream's cache path, avoiding missing imports after cache
  cleanup. The shared preparer creates valid placeholders/handles protected output.
- Removed the two custom Base16 generators. Retained the old responsive 82px/64px
  new-tab logo layout separately; upstream now owns colors, including Glance styling.
- Enable only the required stylesheet preference through package policy, not
  devtools.chrome.enabled. No profile scan, browser kill/restart or user.js writer.
  Existing declared extensions, password-manager and tracking policies are preserved.
- Found the launcher explicitly used the raw flake package, bypassing module policy
  configuration. It now uses the module-configured beta package while keeping the
  exact `-P "Default Profile"` argument and existing desktop actions. Tests inspect
  the actual built unwrapped browser's policies.json, not just declared option data.
- Seven tests cover two palettes/both media-query modes, mode-independent CSS,
  protected profile entrypoints, unchanged user.js/preferences/backup profiles,
  existing policies/launcher, logo layout and runtime output handling. No browser
  starts in tests; no Gecko CSS validation or GUI behavior is claimed. Total Noctalia
  tests: 58, plus 11 safe-suspend tests. Invariants enforce no profile-mutating hooks.
- Full Framework build and native config validation pass with substitutions disabled.
  User rebuilt and confirmed it works. Deployment inspection verified managed imports,
  writable generated chrome/content CSS, active shell/overview services and no recent
  renderer errors. Detailed profile/extension checks and live-versus-restart reload
  behavior were not independently instrumented. Dark/light media-query changes are distinct from new palette reloads;
  upstream has no live-reload hook. Global selection/form accents can affect web
  content; the template is not a complete website theme. Some about-page coverage
  is documented upstream as limited.

VS Code community-template implementation accepted:
- VS Code was installed as a plain package, with its Home Manager module disabled
  and no local Code/.vscode user directories. Enable the module, remove the duplicate
  package-list entry, and declare the selected theme/settings/extension there.
- Consume the pinned community `vscode/vscode.json` verbatim. Pin the official
  Marketplace `noctalia.noctaliatheme` VSIX at 0.0.5 with a fixed hash. It is a theme-only
  extension, with no activation script. Keep manifest/icon immutable; redirect only
  its contributed JSON file to writable XDG state via a package symlink adaptation.
- Register the renderer output in that state path, not upstream's versioned mutable
  extension-directory assumption. No custom manifest, forked color template, settings
  hook or restart script. The existing preparer seeds valid JSON and backs up old
  protected output before extension links are installed.
- Disable the dormant Stylix color target/extension while retaining its intended
  static font settings from the pinned font mapping. Select NoctaliaTheme, disable
  competing auto color-theme selection and auto-updates. Manual installation of other
  extensions remains available through mutableExtensionsDir; managed settings stay Nix-owned.
- Upstream contributes only vs-dark, and its JSON type is dark even when rendered
  with light colors. Preserve/document that classification limitation rather than
  forking it. Do not assume full native light-theme classification or live reload.
- Six tests cover actual CLI extension discovery in isolated dirs, official manifest/
  link ownership, two palettes in both modes, settings/font/update policy, unchanged
  metadata/settings during rendering and bootstrap/legacy output. The packaged CLI
  script runs via Nix Bash because /usr/bin/env is absent in the build sandbox;
  no editor GUI or user profile is opened. Total Noctalia tests: 64, plus 11 suspend.
- Invariants and full Framework build pass with substitutions disabled. Native config
  validation/lint pass. User rebuilt and confirmed it works. Live inspection verified
  the Nix-managed settings and extension links, NoctaliaTheme 0.0.5 selection, declared
  fonts and a writable 0644 runtime palette. Shell/overview remain active. Exact GUI
  reload mechanics and upstream light-classification behavior were not independently
  instrumented. Do not enable the duplicate mutable community catalog
  entry: it targets versioned extension directories outside this registration.

lazygit community-template implementation accepted:
- `noctalia/lazygit.nix` consumes the pinned upstream `lazygit/lazygit.yml` verbatim.
  Its merge hook is not run: that hook writes through the managed config.yml symlink.
- Native LG_CONFIG_FILE loading merges the managed base first and generated overlay
  second. A small package wrapper supplies this list only as an environment default,
  avoiding login-shell dependency while respecting custom env/explicit CLI config.
  Existing Nushell `lg` integration remains unchanged. Shared/Darwin modules are untouched.
- Disable the fixed Stylix color target; keep `gui: {}` so a valid managed base always
  exists even with no other settings. Render the separate writable
  `lazygit/themes/noctalia.yml`, prepared safely before linkGeneration. No color
  generator, config-writing hook, poller or restart process is added.
- Six tests render two palettes/both modes, exercise real lazygit in isolated PTYs
  and temporary git repos, observe expected truecolor ANSI output, prove non-theme
  base settings survive (custom quit key), and verify explicit config flag precedence,
  protected base files, wrapper/default contract and bootstrap/legacy output handling.
  Test-only startup/update/fetch options prevent network and prompts; production
  defaults/keybindings are not changed. No user's repository/TUI is used.
- Total Noctalia tests: 70, plus 11 safe-suspend. Invariants, native config validation,
  lint and full Framework build pass with substitutions disabled. User rebuilt and
  confirmed it works. Live inspection verified the protected base symlink with empty
  gui map, writable theme overlay, ordered wrapper default and active shell/overview
  services. Exact running-TUI hot-reload behavior was not independently instrumented.
- Keep the duplicate mutable community catalog entry disabled: it would reintroduce
  the unsafe config-writing hook. Repo-local config and explicit user overrides may
  intentionally supersede the global theme; no such native behavior is disabled.

fzf community-template/Nushell implementation accepted:
- The pinned repo provides Bash/Fish snippets but no Nushell template. Consume the
  upstream Bash file verbatim; a small fzf package wrapper sources it only in the
  child process before exec. No custom color mapping, Nu eval/translation, shell
  profile hook, Fish universal variable or new keybinding is introduced.
- Keep programs.fzf.enable false, as before, so Atuin/current picker bindings are
  unaffected. Disable only the dormant Stylix color target. Shared packages now
  reference programs.fzf.package: NixOS gets the wrapper; Darwin retains its default
  unwrapped package. Manual pages are retained in the wrapper output too.
- Render only `fzf/themes/noctalia.sh`. The standard preparer seeds a comment,
  safely privatizes protected legacy output and preserves writable data. No apply
  hook or new service. XDG_CONFIG_HOME is resolved per invocation with HM fallback.
- Existing FZF_DEFAULT_OPTS and FZF_DEFAULT_OPTS_FILE survive; native CLI flags
  retain precedence. Repeated top-level invocations don't mutate/accumulate colors
  in the parent Nu session. Each new picker reads the current palette; an already
  running picker retains its process options (no live mutation/reload is claimed).
- Seven tests render two palettes/modes, run real fzf selectors and real Nushell,
  prove repeated parent options stay stable, exercise native option/file/CLI
  precedence, and observe RGB output in isolated PTYs after palette replacement.
  Bootstrap, protected output and hook-free registration are covered. No user shell
  or picker is touched. Total Noctalia tests: 77, plus 11 safe-suspend tests.
- Native config validation, lint, invariants and full Framework build pass with
  substitutions disabled. User rebuilt and confirmed it works. Deployment inspection
  verified the writable generated snippet and per-invocation wrapper; a native filter
  smoke test returned the expected selection and shell/overview services remain active.
  Detailed user keybinding behavior was not independently instrumented.

Security checkpoint activated and verified before remaining app work:
- Remove the compromised Lantian URL and signing key from shared runtime policy
  and the mirrored flake literals. New `checks.<system>.cache-trust` enforces source
  synchronization and rejects the endpoint/key, including Framework runtime settings
  on Linux.
- Full Framework build, cache trust check, all 77 Noctalia/11 safe-suspend tests and
  invariants pass with substitutions disabled. Generated nix.conf was inspected and
  contains neither endpoint nor key. Built/deployed kernel store paths are identical;
  no kernel input, power policy, store artifacts or system services were changed live.
- User activated with substitutions disabled. `/etc/nix/nix.conf` and effective
  `nix config show` exclude both old endpoint and key; nix-daemon is active with its
  restart timestamp updated, and shell/overview services remain active. Revocation
  is accepted. Artifact/kernel integrity review remains separate: removing cache
  trust does not certify old downloads as safe. See security-hardening.md.
- Niri's built-in template is the next theming checkpoint, followed by Nushell/other
  remaining consumers; do not remove the compatibility bridge prematurely.

Niri built-in template implementation accepted:
- `noctalia/niri.nix` enables the shipped built-in `niri` integration unchanged.
  Niri-flake's settings renderer remains the source of the main config; append a
  declarative absolute include of writable `niri/noctalia.kdl`. The upstream hook
  recognizes it and skips editing the read-only managed config.
- Niri 26.04 supports `optional=true`, used so build-time validation can run without
  home files. Activation prepares valid output before linkGeneration. Tests also
  validate the full config with generated output present and reject invalid included
  data; optional doesn't mean invalid content is ignored.
- Remove only the two fixed active/inactive Base16 colors from layout.nix. Keep
  borders enabled/4px, focus ring off, 12px gaps, transparent workspace backgrounds,
  shadow flags, zoom/struts, bindings, rules, inputs, outputs and startup unchanged.
  The stock template changes border/focus/tab/insert/recent-window highlight colors;
  native include merging preserves the separately declared layout properties.
- Six tests render two palettes/both modes, validate complete KDL with the actual
  Niri binary, exercise the stock output/apply hook against a read-only config
  symlink, check generated structure, optional/invalid handling and protected output.
  No compositor is started/reloaded or live config edited by tests. Total Noctalia
  tests: 83, plus 11 safe-suspend.
- Main Niri config is identical across base/light/dark generations; colors are only
  in the runtime include. Native file watching owns reload, not an extra script or
  compositor restart. Cache trust/invariants/lint/full Framework build pass. User
  rebuilt and confirmed it works. Live inspection verified the protected main config,
  writable generated include and active shell/overview services; the real Niri validator
  accepted the complete live config. GUI behavior is user-confirmed, not independently
  instrumented by the structural tests.

Nushell runtime producer implementation accepted:
- Neither pinned built-in nor community catalog has a Nushell entry. Use a small
  local NUON **data template**, rendered by Noctalia's existing engine; no alternative
  generator, service, shell eval or controller. Map the previous fields/bold attributes
  to native terminal/semantic color roles, not another fixed Base16 palette.
- Register a hook-free user template writing `$XDG_STATE_HOME/nushell/theme.nuon`.
  The shared output preparer handles protected output and seeds an empty record until
  first render. Remove both generated light/dark config files and startup copies.
- Retain the prompt-time reader, now externalized in `nushell-theme.nu`, with XDG
  state support and safe missing/empty/non-record/partial-data handling. Successful
  reads alone update the mtime cache; failures keep existing colors and retry on the
  next prompt. Other prompt hooks, keybindings, completions, aliases and shared/Darwin
  modules are unchanged. Noctalia writes inert NUON, never executable shell config.
- Remove the compatibility bridge's Nushell copy path and its unused home argument.
  A regression test proves native output remains untouched across mode requests;
  the bridge still handles remaining consumers (SwayOSD/wallpaper) for now.
- Six real-Nu tests cover two palettes/modes, startup config validation, same-session
  pre-prompt updates, retained hooks/keybindings/completions, unchanged-file skipping,
  missing/empty/nonrecord/partial data, recovery after failed reads, and protected
  output. Total Noctalia tests: 90 (16 bridge), plus 11 safe-suspend tests.
- Native config/cache checks, invariants, lint and full Framework build pass. User
  rebuilt and accepted the result. Live inspection verified the writable NUON output,
  removed old static files, installed reader, successful native data parsing and active
  shell/overview services. Detailed integration behavior was not independently instrumented.
  Existing shells at the default state path can read the new record format; open a
  fresh Nu session once to install the improved reader itself.

Native Noctalia wallpaper migration accepted:
- `noctalia/wallpaper.nix` enables native image surfaces but disables Noctalia's
  separate backdrop. Niri places `^noctalia-wallpaper$` within its own backdrop only,
  with crop and one-second fade; workspace previews remain transparent. Path-only favorites retain the two
  existing mountain images without changing palette/mode when clicked. No automation
  or wallpaper-derived palette selection is introduced.
- V5's mode-aware directories don't directly map/apply these two files at mode change.
  Retain the existing deterministic mode selector in the temporary bridge, replacing
  awww query/img with native `wallpaper-set`. Native errors leave work pending for
  retry. This is still small mode-pair glue, not entirely script-free wallpaper policy.
- Remove the active awww package/startup, switch the Niri layer rule to
  `^noctalia-wallpaper$`, remove monitor-hotplug.service and its udev script. Native
  Noctalia output handling owns reconnects. The awww input/inactive Darkman rollback
  code remain intentionally for now; do not remove the compatibility bridge yet.
- Two added mocked tests cover native light/dark calls, no reverse palette/mode
  writes and failed-IPC retries. Invariants enforce native ownership, fade/zero
  disabled extra backdrop, path-only favorites and no old startup/package/hotplug
  service. A new Niri regression checks the single wallpaper's backdrop placement,
  and full validation includes that rule. Total Noctalia tests: 93,
  plus 11 safe-suspend. Native config/lint/full Framework build pass.
- First live trial exposed a regression: normal wallpaper plus a separate native
  backdrop put images inside workspace previews too. Corrected by moving only the
  native wallpaper surface into Niri's backdrop and disabling the extra renderer.
  User rebuilt and confirmed transparent workspace previews and light/dark fades.
- The old loose awww daemon survived initial activation. Native surfaces, selected
  mountain image and successful light/dark texture changes were verified first;
  then its pinned official `awww kill` IPC retired that exact user backend. Process
  and layer inspection confirmed it exited. Niri was not restarted and no automatic
  migration/process-kill hook was added.
- User confirmed backdrop-only appearance and fades between light/dark images. Live
  inspection verified one noctalia-wallpaper layer, no extra backdrop/awww, the correct
  dark image, removed hotplug service, valid full Niri config and active shell/overview.
  Monitor reconnect and shell-restart behavior remain untested. A Noctalia restart may briefly remove its wallpaper; standalone
  awww isolation is intentionally traded for native ownership. Manual picker choices
  persist until a subsequent mode/forced startup refresh restores the configured pair.

Remaining-consumer audit and Starship implementation accepted:
- SwayOSD has no mode-specific generated style/service config here, but its client
  performs volume mutations as well as drawing OSD. Native Noctalia OSD migration
  is a separate functional checkpoint: preserve current controls/DDC/audio init and
  don't conflate replacing the service with removing a color consumer. No volume,
  brightness, audio-init or lock/authentication changes made in this step.
- Real mode-varying managed outputs still include Starship, swaylock, btop, gdu,
  gtksourceview/gedit, Vencord, Blender, Forge, Xresources and generated environment/
  font files. Some targets write files despite their app modules being disabled;
  enabled-target names alone do not prove actual app use. Audit remaining package/
  Emacs config too before retiring specialisations.
- `noctalia/starship.nix` disables fixed Base16 prompt colors and composes the
  Home Manager-generated base (including presets) with the unmodified shipped
  Starship palette at build time. Noctalia renders that complete template to
  `$XDG_STATE_HOME/noctalia/starship.toml`; no runtime merge or config-writing hook.
- Starship has no include. Keep the base immutable/declarative and set STARSHIP_CONFIG
  to runtime output in session/Nu environment. Prompt format/modules/integration and
  shared/Darwin config stay unchanged. The upstream hook is deliberately not used:
  it scans process environment and writes through the managed config symlink.
- A valid comment placeholder keeps default prompts functional before first render;
  the standard preparer handles protected runtime data. Native Starship reads the
  current output per prompt. A fresh Nu session installs the new config pointer.
- Six tests cover two palettes/both modes, real prompt ANSI RGB, actual computed
  config, verbatim upstream/base composition, immutable base/pointers and bootstrap/
  legacy data. Total Noctalia tests: 99, plus 11 safe-suspend. Native config/cache/
  invariants/lint/full Framework build pass. User rebuilt and confirmed it works.
  Live inspection verified the immutable base, writable complete runtime config,
  native palette without Base16, installed Nu pointer and actual RGB prompt output.
  Shell/overview remain active; detailed user integrations were not independently
  instrumented beyond the automated tests.

Native OSD/control migration accepted:
- `noctalia/osd.nix` enables native output-volume and brightness OSD, disables input
  volume OSD and overdrive, and disables the SwayOSD service. Existing lock-key OSD
  preference remains off; other native feedback/sound settings are not changed.
- User requested bottom-edge OSD placement; both native position fields are
  bottom_center, avoiding the overview topbar. Plain F1–F12 remain unbound by Niri.
  Framework Fn+Esc toggles hardware Fn Lock to make F-keys primary and Fn+F3 volume-up;
  no firmware write/remap was performed. Persistence is reported upstream, not locally
  reboot-tested. User confirmed bottom placement and desired Fn behavior work.
- Niri volume keys call the native volume-up/down IPC with explicit 5% steps and
  native mute toggle. Native audio service updates bar/OSD from one device state,
  capped at 100%. Remove volume-ctl/cache producer and its startup initialization;
  leave any old user cache data alone. Media keys remain playerctl.
- Keep brightnessctl 5% internal steps and existing asynchronous DDC target/catch-up
  algorithm. Replace only its display call with native brightness-osd <actual%>,
  never brightness-set. OSD failure doesn't stop DDC; failed internal control exits
  before displaying/syncing stale values. Runtime target/lock paths move from shared
  /tmp names into the user's runtime/cache directory.
- Preserve the Framework pw-loopback startup command unchanged. Remove SwayOSD
  restart from the bridge; no legacy UI services are explicitly restarted now.
  The bridge still applies remaining specialisations/native templates/wallpaper pair.
- Eight tests mock all brightness/DDC/OSD operations, verify native key wiring/limits,
  preserved audio init, 5% changes/actual-value display, OSD/control failure paths,
  external catch-up, existing lock and invalid actions. No hardware call or user
  control was executed. Total Noctalia tests: 107, plus 11 safe-suspend.
- GUI override inspection found no masking OSD/overdrive settings. Native config,
  cache checks, invariants, shellcheck/statix and full Framework build pass. User
  rebuilt and confirmed it works, including bottom placement/Fn preference. Live
  inspection verified bottom-center output/brightness OSD, disabled overdrive, retired
  SwayOSD, native 5%/mute binds, display-only brightness call, preserved pw-loopback,
  valid Niri config and active native services. External-monitor hardware behavior
  was not separately instrumented by the agent. Noctalia availability gates keyboard volume IPC; brightness mutation
  remains independent of its display-only OSD. Native sound settings still apply.

btop built-in template commit approved (live test deferred):
- Audit confirmed btop is an active Home Manager app with fixed Stylix colors,
  one-second refresh and default (non-vim) keys. Other installed plain packages
  (bat/helix/yazi) have their program modules disabled, so audit actual config/use
  rather than treating every injected Stylix option as an active consumer.
- `noctalia/btop.nix` disables fixed colors, declaratively selects `noctalia`, and
  enables the shipped built-in btop template unchanged. Preserve update_ms=1000,
  vim_keys=false, shared integration and Darwin behavior (only a shared comment changes).
- Runtime theme remains separate/writable at btop/themes/noctalia.theme. The common
  preparer seeds a comment and handles protected old output. Upstream apply.sh sees
  the literal selector, skips main-file edits, then requests btop's native SIGUSR2
  reload. No custom mapper, watcher, merge process or prompt changes.
- Six tests render two palettes/modes, exercise the stock hook with fake process
  tools, preserve the read-only main-config link, and test real btop in an isolated
  PTY. The reload test signals only its own sandbox child and observes the new RGB
  palette without replacing the config. No live user btop process was signalled.
- Total Noctalia tests: 113, plus 11 safe-suspend. Full Framework build, native config,
  cache checks, invariants and lint pass. User explicitly requested committing
  without live testing. Deployment, live palette/native reload appearance and GUI
  behavior remain unverified; automated sandbox tests are not live acceptance.
  No lock/authentication or other remaining target is changed.

Residual routing audit and plain-Emacs commit approved (live test deferred):
- Plain `emacs` resolves to Home Manager's final package with Base16 init; its package
  differed between modes. Doom/Spacemacs wrappers instead use raw emacs-pgtk with
  separate init directories, currently selecting personal doom-one/spacemacs-dark.
  No default Emacs daemon is configured. Do not treat all three routes as one client.
- Swaylock is a real mode-dependent config consumer, used by manual Niri and swayidle
  lock/before-sleep/timeout paths, with custom fingerprint/lid-aware PAM. No lock,
  PAM, timeout, suspend, keyring or authentication behavior is changed by this step.
- gdu/Blender/Forge/gedit/Vencord assets are emitted despite no corresponding active
  app setup found in package/config audit; this is not proof of never-use. bat/helix/
  yazi are plain packages, not enabled HM modules. xterm is installed, so Xresources
  cannot simply be deleted as unused. GTKSourceView styles may serve other apps.
- `noctalia/emacs.nix` migrates only the managed plain route: disable Base16, preserve
  the declared font/opacity expressions, add a runtime theme load path and load native
  Noctalia at startup if readable. Compose no custom theme; render the shipped Lisp
  unchanged to XDG state. A valid empty theme seeds bootstrap/protected output handling.
- Omit the built-in discovery/emacsclient hooks: discovery selects Doom first and
  client reload assumes an unconfigured daemon. No existing session is contacted.
  Running apps need restart/manual theme reload; personal profiles retain their themes.
  Upstream's theme includes Org hide-leading-stars/startup-indent preferences and
  generic fixed/variable-pitch face choices, documented rather than silently forked.
- Six tests render two palettes/both modes and load the actual theme/managed init
  in real batch Emacs, checking color faces, opacity/bootstrap, protected output and
  unchanged personal routes/files. Batch TTY font resolution reports default; source
  checks preserve the original font-spec, but GUI font behavior is not claimed.
- Total Noctalia tests: 119, plus 11 safe-suspend. Full build/native config/cache/
  invariants/lint pass. User explicitly requested committing without live testing.
  Deployment, plain-Emacs GUI appearance and GUI font resolution remain unverified;
  automated batch tests are not live acceptance. Do not test this by changing personal
  Doom/Spacemacs configs or locking the session.

Dormant target/KDE overlay cleanup approved for commit:
- Rechecked declarative home/system package inventory, executable/config routes and
  local Flatpak application list. No configured Blender/Forge/gdu/gedit/Vencord or
  KDE/Plasma installation was found; observed config roots contain generated assets.
  This is configuration evidence, not proof of never-use in transient environments.
- Disable those six Stylix targets only. Keep GTKSourceView styles because shared
  viewers may use them, and Xresources because xterm is installed. Preserve swaylock,
  authentication, Emacs profiles, fonts, cursor, icons and native Qt config.
- The mode-specific XDG_CONFIG_DIRS value came solely from stylix-kde-config. Removing
  that target also stabilizes environment/fontconfig/autostart outputs across modes.
  Only eight mode-dependent managed files remain: Xresources, palette HTML/JSON,
  swaylock config and four GTKSourceView versions.
- New invariants reject the dormant assets/KDE overlay and retain protected consumers.
  All 119 Noctalia/11 safe-suspend tests, cache checks, invariants, lint and full
  Framework build pass. No installed app package or user file was deleted by the
  agent. Activation will remove only HM-owned orphan links; non-HM copies are not
  forcibly deleted. Inherited environment values in old processes can persist until
  a later login; this isn't a live env rewrite.
- User explicitly approved committing and continuing. Activation/desktop-font-icon
  regression checks remain unverified; this is not live acceptance. This does
  not retire the bridge; swaylock/Xresources/GTKSourceView and artifact-integrity
  review/deferred GTK checks still require their own decisions/checkpoints.

Xresources native-renderer commit approved (live test deferred):
- xterm is installed and the live Xwayland database still had Base16 resources.
  Neither pinned catalog has an Xresources entry. Use a small local data template
  in Noctalia's native renderer, not a separate color generator/controller.
- Keep ~/.Xresources managed, including a writable state color fragment through
  native preprocessor include. Preserve declared fonts/cursor and Sxiv font; move
  Xresource/Sxiv colors off their static targets into the shared native fragment.
  No personal app config is scanned or edited.
- A display-guarded native xrdb -merge hook updates the resource database without
  writing the managed main file. No DISPLAY means skip safely. Existing xterm
  windows generally retain their startup colors; new instances read current data.
  No live Xwayland database merge or app launch was performed by the agent.
- Six tests run real xrdb preprocessing/merge on test-owned headless Xvfb servers,
  with TCP disabled and isolated HOME/DISPLAY. Two palettes/both modes reach the
  database; fonts/cursor/unrelated resources remain. Test no-display behavior,
  immutable main file, idempotence and bootstrap/protected output.
- Total Noctalia tests: 125, plus 11 safe-suspend. Cache/invariants/lint/native config
  and full Framework build pass. User explicitly requested committing without live
  testing. Deployment/new-xterm GUI appearance remain unverified; isolated X-server
  tests are not live acceptance.
  This checkpoint does not change swaylock/PAM or remove the compatibility bridge.

GTKSourceView native-renderer commit approved (live test deferred):
- Neither pinned catalog has an entry. A saved legacy Gedit scheme setting is
  still 'stylix', even though Gedit isn't installed. Do not delete the available
  style or silently rewrite app preferences based only on package inventory.
- Reuse the pinned Stylix XML syntax/style definitions, adapting only the 16 color
  placeholders to Noctalia roles at build time and changing the visible label to
  Noctalia. Preserve the legacy scheme ID/lookup filenames so saved selections
  remain valid. No copied/forked syntax style body or standalone color generator.
- Noctalia renders one writable state XML. The four versioned lookup paths use
  out-of-store links; the fixed target is disabled. The common preparer seeds a
  valid empty scheme and handles protected output. No preference writer or reload
  hook; applications may need reopening or scheme rescan to load new colors.
- Six tests compare maintained style definitions, render two palettes/both modes,
  verify lookup links/untouched preferences/bootstrap and load colors with actual
  GTKSourceView 4 and 5 native style managers in separate headless child processes.
  Legacy 2/3 directories remain but those parsers/GUI behavior aren't tested.
- Total Noctalia tests: 131, plus 11 safe-suspend. Native config/cache/invariants/
  lint/full Framework build pass. Only three mode-dependent managed files remain:
  swaylock config and the diagnostic palette JSON/HTML. No lock/auth changes made;
  user explicitly requested committing without live testing. Deployment/live editor
  appearance remain unverified; native manager tests are not GUI acceptance.

Native lock-screen migration requested; authentication preflight accepted:
- User explicitly chose Noctalia's native lock screen. Stage the migration instead
  of enabling unverified automatic locking. Stage one keeps the native screen off,
  all swaylock/swayidle/manual/before-sleep routes unchanged, and no agent lock,
  suspend, fingerprint or actual password attempt.
- Pinned V5.3.0 hardcodes service login; the current login stack includes fprint/lid
  rules while Noctalia fingerprints use D-Bus. An old source comment claims filtering,
  but no filter was found in its reviewed pam_start implementation. Do not rewrite
  TTY/login policy to accommodate the locker.
- Add an exact-context, --fuzz=0 package patch selecting dedicated service noctalia
  for locker password auth only. Add a password-only PAM service requiring pam_unix
  for authentication/account checks, with no nullok/permit/fprint/include. Other
  PAM files (login/swaylock/sudo/greetd/polkit-1) compare unchanged to the live system.
- Build/test the patched native binary; existing 131 Noctalia/11 suspend tests plus
  the new auth-stage policy check pass. This validates compilation/configuration,
  not actual authentication. A manual pamtester preflight must pass before stage 2.
- Stage 2 will review native fingerprint/account semantics, secure grace/empty-password
  defaults, compositor recovery and native lock-before-sleep/DPMS coordination,
  then reroute manual/idle locking in a separate checkpoint. Do not claim PAM/fingerprint
  parity or safe lock/unlock merely from unit tests.
- User activated stage one and manually confirmed a valid password succeeds and an
  invalid password fails. Dedicated PAM is deployed; Noctalia/working locker routes
  remain active as configured. This accepts only the password-stack preflight, not
  fingerprint/native-screen/unlock/rendering/suspend behavior. Full instructions:
  docs/noctalia-lockscreen-migration.md. The agent never requests secrets.

Native lock stage-two manual trial accepted:
- Stage-one auth foundation committed as 4f39d5d after the user confirmed correct/
  wrong-password behavior. Dedicated PAM/global login/swaylock stacks remain unchanged.
- Enable native lock with grace=0, allow_empty_password=false, no desktop capture,
  no transitions and all outputs. Mod+Shift+X now requests native lock. Native logind
  Lock is the only listener; remove the duplicate swayidle lock event.
- Keep swaylock at idle 300s and before-sleep, old monitor power 305s and safe-suspend
  310s. Native lock_before_suspend=false and native idle remains disabled during this
  manual trial; automatic cutover is a later stage, not silently enabled here.
- Fingerprint review: native fprintd Claim("") is current D-Bus user, claim is released
  on stop, paused during sleep, and password submission stops the reader. A successful
  native match bypasses PAM account checks; not identical to old account-policy paths.
  Existing fprintd/lid root policy is untouched. Password fallback remains independent.
- Four policy tests assert defaults/manual route, no competing logind listener,
  retained automatic fallback and strict password stack, without any auth/session
  action. Total Noctalia tests: 135, plus 11 suspend. Full build/config/cache/auth/
  invariants/lint pass; no actual lock/fingerprint/DPMS/suspend test was performed.
- User must save work and validate TTY/password recovery, apply while unlocked and
  manually test native password/rejection/fingerprint/all-output coverage. User
  activated and confirmed password and fingerprint unlock work. Live inspection
  verified native secure defaults/manual route, retained swaylock idle/pre-sleep,
  and active shell/overview. Wrong-password UI behavior, all-output coverage and
  sleep/idle recovery were not separately confirmed. Never kill/restart a locked
  client as an unlock strategy; see the migration guide.

Native lock stage-three automatic cutover prepared:
- Native lock_before_suspend=true; remove the last swayidle pre-sleep hook. Native
  logind Lock/sleep-delay is the sole listener/locker. Keep swayidle as inactivity
  timing source and all audio/Caffeine/lid/power policy unchanged.
- Preserve 300/305/310s: native lock, coordinated native dpms-off/on, then safe-suspend
  --require-lock. The idle-only guard resolves graphical session identity, requires
  LockedHint=yes and blocks on missing/error/unknown state. Manual safe-suspend
  remains unchanged. Existing sleep-blocker checks run first and never bypass logind.
- Pinned native plain Suspend sets a skip-lock flag before detached power execution;
  a failed command can leave it stale. A small strict-context policy patch respects
  configured lock-before-suspend instead. No auth/protocol implementation is replaced.
  Session panel uses Lock and Suspend and native power override uses the same guarded
  helper. Plain native suspend while unlocked fails closed, intentionally.
- Retain installed swaylock/PAM as rollback only; its old style consumer still exists
  until native automatic acceptance. Do not treat static policy or the locked hint as
  proof of every compositor/render/sleep condition. No real session action by agent.
- Six native-lock policy tests plus 19 mocked safe-suspend tests cover routes,
  timings, native power policy, session lookup/locked-hint failures and blocker
  precedence. Total Noctalia tests: 137. Patched binary/full Framework build/native
  config/cache/auth/invariants/lint pass. Live idle/DPMS/suspend/resume/lid/output
  checks are pending and must be performed one at a time by the user after saving
  work and preparing recovery. Current logind delay bound was read as five seconds.

Stage-three first activation inspected; timer-only swayidle correction prepared:
- Noctalia/swayidle/overview active; expected native timer routes deployed; native
  sleep-delay inhibitor acquired. No real lock/power/sleep action triggered by agent.
- Found swayidle 1.9 `BlockInhibited` parse warning: removing all non-timer events
  leaves its bus uninitialized, breaking logind idle-inhibitor monitoring. The
  guarded suspend helper still checks sleep blockers, but idle lock/DPMS inhibition
  must not be assumed reliable in this first activation.
- A strict one-line package patch includes timers in need_logind, restoring bus/
  property monitoring without dummy hooks or another sleep-delay listener. Remove
  duplicate unpatched swayidle package entry; HM installs the configured package.
- Regression verifies patch/no dummy events; 137 native tests, 19 mocked suspend
  tests, auth/cache/theme checks, lint and full Framework build pass. User activated
  the correction; the running executable matches the patched package, its system-bus
  connection exists and the startup warning is gone. All three services remain active
  and native sleep-delay inhibition remains held. Live inhibitor/idle/sleep tests are
  pending; no automatic behavior is yet accepted or committed.

Stage-three manual recheck accepted: user confirmed native UI wrong-password
rejection and correct-password unlock after activation of the swayidle correction.
No agent authentication/session action was performed. Idle/DPMS, sleep/lid,
reader-unavailable fallback and multi-output coverage remain unconfirmed; this
manual recheck does not accept automatic locking or authorize fallback removal.

Stage-three idle observation accepted as reported: display went black; a key press
restored the native lock screen, not an unlocked desktop. Services remain active,
native lock-confirmed/unlock-requested events are present and native sleep-delay
inhibition remains held. Exact idle timings, all-output coverage, actual suspend/
resume, lid, reader-unavailable recovery and audio/Caffeine inhibition are not proven
by this observation and remain separate checks. No agent session action was performed.

Stage-three suspend trial blocked by immediate resume:
- User reports manual suspend does not stay asleep. Three user-operated attempts
  entered kernel s2idle and returned within 2–4s including preparation. Noctalia's
  locked confirmation preceded delay release, and the delay was reacquired on resume.
- Read-only diagnostics: CanSuspend=yes, no high-level sleep blocker at inspection,
  last wake IRQ 9 (generic ACPI SCI), only s2idle available, no RTC alarm. Goodix USB
  wake was already disabled. Nearby fprintd cleanup/claim warnings are not proof of
  cause. No wake flags, auth settings, kernel or hardware state were changed.
- Same boot/kernel previously stayed suspended overnight, before this cutover, so
  retain migration-interaction hypotheses. Need hands-off/lid-still confirmation and
  controlled user trials before attribution. Sustained sleep/resume acceptance,
  fallback retirement and the security checkpoint commit remain on hold.

Suspend clarification: first two attempts used the combined power button/sensor;
logind attributes them to Niri, and the third request to systemctl. Lid closes at
5/12s after resume fell within live logind HoldoffTimeoutUSec=30000000 and no new
lid suspend was requested. Preserve that hotplug/dock safety delay; do not classify
those short lid tests as proof of broken lid policy. Next user-only test is a
keyboard-initiated, lid-open, fully hands-off suspend trial to separate spontaneous
wake from power-button/sensor/lid interaction. No policy/device changes made.

Stage-three keyboard suspend accepted: user confirms Mod+Shift+S works. Read-only
logs show kernel s2idle entry 12:26:53 and exit 12:29:23, native lock confirmed before
delay release, delay reacquired on resume, then an unlock request. All three services
remain active. No auth/wake policy was changed. This accepts the sustained keyboard
safe-suspend path, not power-button behavior, exact low-power residency, all-output
coverage, a particular unlock method, lid handling or the automatic 310s route.
Next user trial is lid closure outside the 30s post-resume holdoff.

Lid-trial logs verified after user reported completion: lid-close 12:36:34 requested
suspend, kernel entry 12:36:35 and resume on lid-open 12:36:56. Native lock confirmation
preceded delay release; native inhibitor reacquired and unlock requested after resume.
All three services remain active. User then explicitly confirmed native lock-screen
presentation after lid-open. Accept that observation and the logged lid sleep/wake
path; normal unlock on this trial, particular auth method, no-flash behavior and
all-output coverage were not separately confirmed. Power-button interaction and
full automatic 310s suspend/inhibitor validation remain open.

Native-idle replacement approved and prepared (not activated):
- Full automatic trial: lock 12:49:46, monitor off 12:49:51, no kernel sleep. Full
  journal exposed `safe-suspend: command not found` at 12:49:56; swayidle's PATH is
  Bash-only. Do not describe this trial as suspend success or another wake failure.
- Extract one explicit-PATH niri/safe-suspend-package.nix and use its absolute
  executable from the keyboard and native power backend. Retain profile command,
  blocker parsing, locked-hint guard and manual behavior. No auth algorithm change.
- Native idle.nix uses built-in lock=300s, screen_off=305s (native monitor restoration)
  and lock_and_suspend=310s; behavior_order fixed, fade=0 and locked_timeout=0 preserve
  elapsed timing across lock. Native lock-and-suspend delegates to the absolute guarded
  power backend. No custom timer/resume controller and no competing swayidle unit.
- Disable swayidle/remove its temporary patch. Keep fallback swaylock/PAM/style and
  native sleep-delay patch. Do not bundle bridge/specialisation cleanup.
- Reviewed native ScreenSaverService's BlockInhibited subscription and IdleManager
  inhibitor gating: existing audio idle:sleep watcher and Caffeine are supported;
  retain all hardware/lid/tuned policy. GUI idle/session override audit found none;
  state file left untouched. Live inhibition behavior remains to be validated.
- Eight policy/probes cover native scheduling/actions, elapsed timeout choices,
  secure defaults, rollback, sole scheduler, empty-PATH backend resolution and actual
  configured-binary parsing. 139 Noctalia + 19 mocked suspend tests, full Framework
  build, auth/cache/theme checks and format/lint pass. No agent session/power action.
- Next user rebuild while unlocked; inspect no running swayidle, native registered
  behaviors and native sleep-delay before another six-minute idle trial. Live native
  idle acceptance and power-button interaction remain open; do not commit as accepted.

Native-idle deployment verified after user rebuild:
- Noctalia/overview active; swayidle not-found/inactive with no remaining process.
- Current invocation registers native lock=300s, screen-off=305s and suspend=310s
  with locked_timeout=0. Native sleep-delay acquired and logind idle monitor active.
- Live config has zero fade, native action/order settings and the absolute guarded
  power backend. GUI idle/session overrides are empty. No agent session action.
- Deployment is verified, not automatic-suspend/inhibitor acceptance. Next user-only
  six-minute hands-off trial followed by normal-key wake and kernel-log validation.

First native-idle trial reaches suspend:
- Native lock 13:14:05, screen-off 13:14:10, suspend 13:14:15; lock confirmed before
  native delay release. Absolute override launches and logind accepts systemctl.
- Kernel entry 13:14:16, exit 13:14:29; delay reacquired and all behavior resume
  callbacks run, followed by unlock request. No helper errors; native services
  healthy and swayidle absent. Native scheduling/backend are verified in logs.
- About 13s entry-to-exit is not enough to assume intended wake timing. Ask whether
  the user pressed the key at resume versus spontaneous wake; acceptance of staying
  asleep until return and live audio/Caffeine inhibition remains pending. No agent
  session or hardware action performed.

Native automatic sleep/key-wake accepted: user explicitly confirms their key press
caused the 13:14:29 resume. Combined with registered timings, native action logs,
lock-before-delay-release, actual kernel sleep and successful backend invocation,
this accepts the observed native automatic route. No claim of long-duration low-power
residency, all-output coverage or power-button fix. Next live regressions are Caffeine
and existing audio inhibition; rollback/theme consumers and uncommitted checkpoint
remain pending those checks or explicit user disposition.

Native Caffeine integration probe verified after user enabled it: idle/block
inhibitor labelled Caffeine held by Noctalia, aggregate BlockInhibited includes idle,
and native logs acknowledge logind inhibitor acquisition and systemd idle inhibit
active at 13:25:06. Services healthy. This accepts acquisition/detection, not a full
inhibited-idle interval. Next user disables Caffeine and starts audio playback to
isolate audio's idle:sleep blocker/native recognition; no agent state change.

Audio acquisition/native recognition verified with Caffeine off: user started
playback; Audio Playback holds sleep:idle/block and aggregate BlockInhibited includes
sleep/idle. Native logs confirm Caffeine release at 13:28:15 and new idle inhibition
at 13:28:33. Audio watcher/native shell/overview active, swayidle absent. This accepts
independent acquisition/recognition plus Caffeine release, not an unperformed timed
idle-suppression or suspend-block challenge. Next user pauses playback to verify
blocker/native-state release. No agent playback/power state change.

Audio release integration verified after user paused playback: native release log
13:29:43, no Audio Playback/Caffeine idle:sleep blocks remaining, only Niri's normal
handle-power-key block in aggregate state. Native shell/overview/audio watcher healthy
and swayidle absent. Basic inhibitor acquisition/recognition/release cycle passes;
full-duration inhibited idle and actual suspend-block challenges were not run.
Core native idle/sleep route now has live evidence; power-button interaction,
reader-unavailable password fallback, external outputs and extended inhibition stay
explicitly open. Retain fallback/theme consumers/bridge and request user checkpoint
commit or further validation disposition rather than claiming all gates accepted.

User authorized checkpoint commit with follow-ups explicitly documented, not
reclassified as passed. Track combined power-button wake investigation, full-duration
Caffeine/audio suppression/suspend-block challenges, reader-unavailable password
recovery and external-output/hotplug coverage. Keep swaylock/PAM/style and theme
bridge/specialisations; retirement requires a separate review and wallpaper policy
resolution. Current native automatic sleep/key-wake and basic inhibitor cycles have
live evidence. Update recovery guidance for the now-active native PAM dependency;
never remove it or restart a locked shell as an unlock procedure.

Origin rebase performed onto a44373c with all 31 local commits replayed/signed:
- Keep every origin lock node/root reference, adding only local-only input graphs;
  retain Noctalia/community pins. Other lock files match origin. No blanket update
  or shared-input downgrade. Backup retains the original tip and checkpoint history.
- Preserve origin's GTK/Papirus move, newer Vicinae and shared/Darwin additions;
  retain native Qt config ownership rather than restoring static Kvantum files.
- Compatibility fixes: explicit GTK/Xresources cursor retention for new Stylix,
  new Vicinae common-header include path in the real parser probe, and libxcb for
  origin's Pi 1.3.0 Linux native addon. No versions/hashes were rolled back.
- Both native patches apply with --fuzz=0 against the resolved pinned V5.3 source.
  All 17 Linux checks pass, including 139 Noctalia and 19 suspend tests and a new
  lightweight pinned-provider/standard-kernel aggregation dispatch regression. Hermi and
  macbook derivation evaluation passes; this is not ARM/Darwin runtime acceptance.
- Full Framework build passes, including the newly compiled CachyOS 6.18.52, initrd
  and Home Manager generations. Main nixpkgs' certificate-aware aggregator was
  incompatible with the pinned provider's module format; Framework now uses the
  matching provider helper for that kernel/stdenv, while standard kernels retain
  main's new helper. Both dispatch cases evaluated. No fabricated certificates,
  kernel/signing-policy changes or dropped Keychron module. Existing provider
  MODULE_SIG-disabled policy is preserved, not upgraded to signature enforcement.
- No activation/live hardware actions performed. Prior GUI acceptance remains for
  the pre-rebase stack, not these updated dependencies.
- See [origin rebase validation](noctalia-origin-rebase.md) for lock policy, compatibility
  fixes, checkpoint hash mapping and final validation status.

First rebased boot: kernel 6.18.52-cachyos confirmed; Home Manager activation failed:
- System HM unit ran before login and the old noctaliaThemeLock tried creating
  /run/user/1000 without permission. Home files remained from an older generation;
  the Nu warning referenced raw Atuin 18.19.0, while the system profile supplied the
  18.23.0 wrapper. Bridge waits failed-closed on that failed system activation.
- Fix prepared: canonical persistent state-home lock shared by HM/worker, with
  legacy runtime lock retained in the same acquisition order for upgrade/rollback.
  Never manufacture /run/user dirs. Export an existing owned runtime for native
  user-service integration; query/stop legacy Darkman only with a bus, before locks.
- Defer requests without runtime; guard overview ensure on session-bus availability.
  Normal forced HM requests invalidate only the applied-generation cache, so later
  session startup reasserts the selected specialisation even for the same cached
  generation/mode. Explicit state-home/lock paths agree; GUI settings untouched.
- 154 tests include real private hook/flock fixtures, fake systemctl, mocked generation
  activations and real current Nu integration/warning probes. Full Framework build,
  invariants and lint pass. Current Atuin wrapper produces unique names; shared/Darwin
  config and key behavior aren't modified. Redundant wrapper retirement stays separate.
- User should rebuild switch while unlocked, then open a fresh terminal. Verify HM
  success/current config and bridge before checkpoint commit. Cold-boot validation
  remains pending a later user reboot; no agent activation/service/auth/power action.

Live activation retry exposed a readiness cycle after lock/link stages succeeded:
- Home Manager waited in sd-switch for noctalia-theme.service's oneshot startup;
  the worker waited for the system HM activation. Killing nh did not stop that unit;
  the system activation later timed out/failed. Native Noctalia remained running.
- Fix prepared: finite worker Type=exec marks startup before awaiting HM. Keep the
  HM wait before locks/activation, pending-event semantics, identical variant units
  and on-failure retry. Normal activation ensures the path watcher asynchronously.
- New service snapshot/invariant checks reject oneshot readiness; private hook
  fixtures verify pre-session deferral, post-session path restoration and dry-run/
  nested skips. Total 158 Noctalia tests and full Framework build pass. This is not
  a successful live sd-switch/cold-boot test; both remain pending user validation.
- User recovery stops only noctalia-theme.path/service (not native shell/locker),
  then applies the completed fix while unlocked. Do not retry an old oneshot unit
  blindly or activate/restart services as an agent. No checkpoint commit yet.

Readiness-fix live retry verified: HM finished successfully 11:11:02–11:11:06;
finite Type=exec worker refreshed light mode and exited at 11:11:09, path watcher
waiting. Current Nu config sources unique-name 18.23.0 integration, not reported
old 18.19.0 script. User still sees the old store path when pasting; two pre-rebuild
Nu processes remain. Need a fresh terminal/paste check and distinguish emitted
warnings from editable clipboard text; no clipboard read or new workaround applied.
Activation cycle now has live evidence; cold-boot/new-terminal acceptance pending.

Activation-readiness recovery and fresh terminal accepted: user confirms `echo test`
works normally and copy/paste no longer presents the old warning. HM success,
Type=exec finite worker completion, path restoration and current unique-name Nu
integration were verified read-only. No clipboard contents inspected; no Nu/paste
binding workaround applied. Full cold-boot validation remains open pending a later
user reboot; do not equate warm recovery with pre-login acceptance. Await checkpoint
commit/cold-boot disposition; source changes remain uncommitted.

Pre-session activation fix verified after the user's further reboot:
- User confirms the fresh-terminal/paste fix persists. Kernel remains 6.18.52-cachyos.
- System HM completed successfully 11:32:07–11:32:10, before user runtime/daemon
  availability, skipped reload and explicitly deferred the theme request.
- Session startup worker Type=exec began 11:32:14, applied/refreshed light mode by
  11:32:19, then exited normally; watcher waiting, zero worker restarts, native
  shell/overview active. No failed system/user units remained at inspection. A
  transient degraded-session notice listed no failed services and completion passed.
- Accept the observed warm/readiness, fresh Nu/paste and reboot/pre-login path;
  retain unrelated hardware/auth/output follow-ups and fallback/theme consumers.
  Finalize the signed checkpoint after checks; no agent activation/service restart.

Native wallpaper-pair checkpoint accepted: image selection independent of HM bridge.
- Reviewed pinned V5.3 directory/rotation, startup/mode hook and IPC implementations.
  Use native started/theme_mode_changed hooks with a small external script, not
  rotation, another service/poller, or a change to wallpaper browsing/palette policy.
- Separate runtime flock, current resolved mode queried under lock (not stale event
  env), bounded native wallpaper-set for the existing pair. Since async native
  hooks discard stdio, bounded logger calls record selection/errors explicitly.
  No HM/build/restart, mode/palette/settings rewrite, hardware, idle/auth or
  shared/Darwin changes.
- Bridge retains only remaining app generation/native-template refresh work; removes
  wallpaper paths/env/IPC. Refresh errors keep pending work. Existing boot-safe lock,
  deferred request, Type=exec readiness and cross-variant invariants stay intact.
- 14 new rendered-hook/private IPC tests, total 172 Noctalia + 19 suspend tests,
  all 17 Linux checks and full Framework build pass; lint/diagnostics clean.
- User rebuilt unlocked and accepted the requested mode/appearance check. Shell
  startup 14:06:03 selected light via native hook at 14:06:04, then dark 14:06:13 and
  light 14:06:17; Auto restored, native getters confirmed light/matching mountain.
  Thus startup hook passed during the rebuild; this was not a fresh OS boot test.
- Native/overview remained active without mode-triggered restart; one internal
  wallpaper layer, no extra backdrop. HM success, bridge normal completion/zero
  restarts, watcher waiting, no failed user units. Read-only agent verification.
  Finalize signed checkpoint. External/reconnect/restart visual coverage, fresh
  OS boot of this policy and fallback/security retirement gates remain.

All user-requested community template IDs now have accepted implementations. Reuse upstream files rather than authoring replacements.
Files/GTK3 checks and remaining E3 targets (Niri/Nushell/other apps), the compatibility
bridge and the separate compromised-cache follow-up are not marked complete.

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

The independent **native wallpaper-pair policy** has passed user-operated startup
and mode-switch checks and read-only verification. Keep the bridge for its remaining
consumers; do not remove security recovery merely because wallpaper is decoupled.

Next close remaining lock/inhibitor/reader/output gates, one user-operated test at a
time, and audit remaining mode-dependent consumers before retiring fallback styling,
the temporary bridge and HM specialisations. Full-duration Caffeine/audio suppression,
reader-unavailable password fallback, external outputs and the separate power-button
interaction remain open. Independent Atuin-wrapper and inactive-code cleanups should
stay separate. Phases A–D and the native renderer migration are already done; do not
repeat the old Phase A recommendation. A fresh OS boot and external/reconnect checks
of this new wallpaper policy remain deferred, not implicitly passed by shell startup.

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
