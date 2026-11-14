# Umbriel — the configured Wayland session

Status: **Umbriel is the sole/default session** (2026-11-07). The earlier
dual-session trial with Niri ended when the owner requested Niri's removal;
Niri, its Home Manager module, flake input and template were retired. Session
startup, native Alt+Tab and basic smoke behavior were user-confirmed during the
trial. Portal, lock, power and broader runtime acceptance rely on the same
invariant checks plus the user's ongoing experience; the agent never launches a
compositor, portal, lock or authentication action.

## Pins and scope

Umbriel comes from its upstream flake, overlaid in `lib/overlays.nix`:

- `umbriel` input: `github:noctalia-dev/umbriel/cachix` at the revision pinned in
  `flake.lock` (currently `814d761`). Upstream has no tags or GitHub releases yet:
  the `0.1.0` package version comes from the repo's `VERSION` file, and the exact
  code is the commit (`umbriel --version` prints `0.1.0 (814d761)`). The `cachix`
  ref is force-pushed to the latest commit whose x86_64/aarch64 builds upstream CI
  pushed, so routine bumps substitute from `umbriel.cachix.org` instead of
  compiling. Older revisions are not retained; pinning one compiles locally
  (measured ~100 s here).
- Compositor and `xdg-desktop-portal-umbriel` come from that same input, so the
  portal protocol surface (including InputCapture) matches the compositor.
- nixpkgs still supplies the native NixOS module and `programs.umbriel` options;
  only the package and portal are overlaid. Do not set
  `inputs.umbriel.inputs.nixpkgs.follows`: matching the flake's own nixpkgs pin is
  what makes the cache paths hit.
- `umbriel.cachix.org` and its public key are trusted in `shared/caches.nix` and
  the flake's `nixConfig` (kept in sync by `checks.cache-trust`).
- The old niri input/caches/overlay were removed with the session; re-adding niri
  would be a deliberate design decision, not a rollback.

`modules/desktop/umbriel.nix` enables the native NixOS module on Framework and
carries the shared desktop session bits (portals, XDG integration, polkit,
gnome-keyring/PAM hooks). A symlink-joined package changes the desktop/start
launcher environment, not the compositor binaries, native service, session
targets or portal implementation. The native Home Manager module is imported
from the same flake revision, supplied as an external argument by Framework's
integration (using HM pkgs in imports directly causes recursion). Configuration
stays immutable and declarative.

## Updating Umbriel

The input tracks the `cachix` ref, and CI moves that ref only after it has pushed
the builds to `umbriel.cachix.org`. A normal bump therefore downloads instead of
compiling:

1. `nix flake update umbriel` (or the `devenv` shell's `flake-update` task when
   updating every input). A full `nix flake update` keeps Umbriel's nested
   nixpkgs at the revision from its own lock, so cache paths stay valid.
2. `nix build .#checks.x86_64-linux.umbriel` to validate the generated
   configuration with the new binary. This fails if upstream renamed or removed
   a setting, before you switch.
3. `rebuild switch`, then reboot. greetd caches its session list from boot and
   the running compositor is not restarted by a switch
   (`restartIfChanged=false`), so a reboot is the reliable way to pick up both
   the new launcher and binary.
4. Roll back with git (`git revert`, or restore the previous `flake.lock`) and
   rebuild. An older revision may no longer be retained on
   `umbriel.cachix.org`, in which case it compiles locally (~100 s).

## Session environment and startup

The upstream launcher does not enter a Nushell login profile. The small
umbriel-session.sh wrapper loads the root-owned declarative Home Manager session
variables from the current account's per-user profile, exports its bin path and
the patched XKB root, then execs the unmodified native start-umbriel. A missing
HM profile fails clearly rather than starting a partially configured session. It
never evaluates arbitrary pasted commands or changes the user's default shell.

The XKB root must be present **before** Umbriel loads/validates its keyboard config;
putting it only in [environment] is too late for initial keymap validation. The
config also publishes it. Model/layout/options match the configured
pc104/us-umlauts/lv3:ralt_switch setup.

Before the compositor starts, the wrapper stops a `graphical-session.target` left
active by a previous session. Logging out removes only the logind session; units
such as Noctalia and the overview watcher live in the persistent user manager
and otherwise survive with a dead Wayland socket, so the new session would not
start fresh copies. Clearing the target also stops a previous compositor that is
still running. A reboot is still required after an activation that changed the
session entry itself, because greetd caches its session list from boot.

The upstream unit is **Type=notify**, and the same package's binary provides the
readiness notification, so keep that pairing. start-umbriel imports the loaded
session environment into the user systemd manager before
`systemctl --user --wait start umbriel.service`, then tears the session down via
umbriel-shutdown.target. Reviewed startup publishes display/IPC/configured
environment, then starts umbriel-session.target/graphical targets. Keep that
native lifecycle and verify it live; offline checks do not prove portal readiness
or session cleanup.

Noctalia and existing user services start through graphical-session.target, not
another `noctalia` autostart. Umbriel owns Xwayland through its packaged
integration. The sole configured startup command preserves the existing 0.5s
Framework pw-loopback initialization, with absolute executable paths. Audio
keep-alive/watcher, brightness/DDC helper, tuned, root fingerprint/lid
management, guarded suspend and native idle stay intact. No lid hook, second
idle scheduler or power-key binding is added; logind keeps its policy. The
power-button backlog remains deferred.

## Appearance, palette and overview

- Scrolling layout, 12px gaps, half-width initial windows, 75/50/25% extent presets,
  4px borders, 16px corners, no compositor blur/shadow added.
- Internal output scale 1.4 and DP-3 4K/120 scale 1.25 retained declaratively, VRR
  always, vertical workspace axis. At least nine dynamic workspaces are reserved on
  those outputs for existing numeric shortcuts; this can show more empty previews
  than the runtime workspace list.
- Overview zoom 0.5, no workspace wallpaper mirroring or background blur, and
  transparent workspace/tint colors. Native Noctalia remains the sole wallpaper
  renderer with its extra backdrop disabled.
- Reuse the maintained Noctalia Umbriel template verbatim as a native user entry.
  Do **not** run its apply.sh: it can copy over the managed main TOML. The declarative
  main includes a separate writable optional noctalia.toml, prepared without writing
  through links. Main layout/alpha choices override included colors intentionally.
- The overview watcher selects Umbriel by the active desktop and its socket;
  never a stale other-compositor socket. Umbriel uses its overview subscription
  and initial snapshot without half-closing that socket. It hides panels/bar
  before initial state and closes orphaned panels on exit.
- Bar capsules, text, fonts, clock, spacing and widgets are unchanged. Native
  overview-type-to-launch is off. Topbar UI work is a separate task.

## Bindings and explicit differences

All declared key positions are mapped from `umbriel/bindings.nix` into Umbriel
actions (wheel names translated). Alt+Tab is additionally registered for the
native Noctalia window-switcher. Originally this was the `hold` command: hold
Alt, press Tab to cycle and release Alt to select. On 2026-11-14 the overlay
opened and cycled, but neither releasing Alt nor Enter switched windows, so the
binding now runs without `hold`. See [Alt+Tab switcher notes](umbriel-alt-tab-switcher.md)
(backlog NOC-05). Once open, Noctalia handles Shift+Tab/backward navigation
and Escape/cancel. Pinned IPC accepts hold, not a fabricated reverse argument, so
no separate initial Alt+Shift+Tab command is promised. Repeat is false and no
locked-session exemption is granted. Terminal/launcher, close, overview,
focus/move/output/workspace, tabbed/floating, size presets, lock, guarded
suspend, media/5%-volume and brightness helpers retain corresponding actions.
Plain F1–F12 are not intercepted. Mod+Shift+D uses Umbriel's own output-toggle.

Semantic differences versus the generic (Niri-style) binding vocabulary:

| Key | Difference |
|---|---|
| Mod+Ctrl+C | Centers focused column, not all visible columns |
| Mod+Ctrl+R | Sets secondary extent to 0.5, not automatic-height reset |
| Mod+Period | Uses consume-or-expel-right, not unconditional expel-only |
| Mod+Ctrl+F | Toggles maximize-to-edges, not expand-to-available-width |
| Shift+Print | Region selection, not a focused-window-only screenshot |
| Print / Ctrl+Print | Native Noctalia region/fullscreen capture |
| Wheel workspace/move bindings | Native Umbriel cadence; no 150ms cooldown |

Mod+Shift+Ctrl+Q keeps the explicit unconfirmed session-exit shortcut; ordinary
quit bindings use the compositor's confirmation. No locked-session exit exemption
or additional locked-key capability is granted.

## Portal and security boundaries

Umbriel's portal advertises ScreenCast and Screenshot; its per-desktop routing uses
those interfaces while GTK handles Settings/default interfaces. Do not restart live
portals as an agent to force an appearance of success; verify sessions after user
entry.

All six current PAM files, native locker/idle configuration, logind settings and
the generated compositor config are unchanged by the former trial and remain
checked. Native source review found three-second lock-surface handoff, opaque
fallback blank, presented-frame confirmation and retained locked state after
client destruction. This is source evidence, not a real lock/rendering or
suspend test. Preserve password/TTY recovery and the previous boot generation.
Never kill/restart a locked Noctalia as recovery.

The [reader/output/power backlog](noctalia-backlog.md) stays deferred. Never use a
compositor transition for sensitive unattended work before normal lock behavior
has been user-checked.

## Validation completed

Full Framework build and all x86_64-linux checks pass, including `cache-trust`
and the Umbriel session check. These include:

- 183 Noctalia tests, including compositor-selection and Umbriel overview probes.
- Twelve Umbriel probes: actual flake-binary config validation, native renderer in
  both modes, immutable main preservation, malformed optional data rejection,
  binding/policy checks, session desktop entry, private fake-launcher
  HM/Nushell/XKB environment tests (including the real generated HM profile with
  unset optional variables), stale graphical-session cleanup before the native
  launcher, provider/routing inspection and the native held-switcher binding. No
  Wayland, D-Bus, real switcher/focus operation or device connection.
- Eight Greeter and 19 mocked suspend probes; no authentication performed.
- Default/PAM/bar/idle/lock/logind invariance and a constant Umbriel main config
  across light/dark specialisations; no runtime output managed as a store file.

No compositor session is launched by the agent. Visuals, input handling,
lock/unlock, actual portals and power behavior are established by the user.

## Upstream idle-redraw and explicit-sync fixes

The previous nixpkgs pin (`0-unstable-2026-10-16`, `5cea311`) predated upstream
fixes `5b66788` (avoid redraws for unchanged surface commits), `e65cc65` (suspend
hidden windows and stop their frame callbacks) and `a2462e71` (latch explicit-sync
commits until the acquire point signals; frame pacing with VRR and direct
scanout). The flake pin (`814d761`) includes all three. Upstream issue #473
documents idle CPU/GPU work scaling with output refresh rate; the fix reduced one
reported idle case to roughly 1%.

This is a compositor issue, not a tuned or power-profile failure. The panel itself
supports VRR from 30–120 Hz, and Umbriel already reports adaptive sync enabled.
Do not disable VRR or tune clocks to compensate.

## User-only recovery notes

Keep the established TTY/password/previous-generation recovery routes. If a
session is locked or unresponsive, use the established recovery rather than
blindly restarting the locker/compositor. Mod+Shift+Ctrl+Q ends the session and
its apps; a normal confirmed session exit (Mod+Shift+E) is preferred with saved
work. Restarting the machine via reboot remains the reliable way to pick up
changed session entries or binaries.
