# Umbriel alongside Niri — retained dual-session setup

Status: **owner chose to keep both for ongoing experiments** (2026-10-23).
Umbriel session startup/basic smoke and native Alt+Tab are user-confirmed.
Comparative performance and broader runtime coverage are not certified.
Niri remains the Greeter default and a selectable recovery session. No compositor,
portal, hardware control, lock or authentication action was performed by the agent.

## Pins and scope

Umbriel comes from its upstream flake, overlaid in `lib/overlays.nix`:

- `umbriel` input: `github:noctalia-dev/umbriel/cachix` at the revision pinned in
  `flake.lock` (currently `814d761`, version 0.1.0). The `cachix` ref is
  force-pushed to the latest commit whose x86_64/aarch64 builds upstream CI
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
- Noctalia remains the reviewed/patched V5.3.0 pin with its native Umbriel backend.
- No compositor default change. No topbar redesign.

`modules/desktop/umbriel.nix` enables the native NixOS module only on Framework.
A symlink-joined package changes the desktop/start launcher environment, not the
compositor binaries, native service, session targets or portal implementation.
The native Home Manager module is imported from the same flake revision, supplied
as an external argument by Framework's integration (using HM pkgs in imports
directly causes recursion). Configuration stays immutable and declarative.

## Session environment and startup

The upstream launcher does not enter a Nushell login profile. The small
umbriel-session.sh wrapper loads the root-owned declarative Home Manager session
variables from the current account's per-user profile, exports its bin path and
the patched XKB root, removes a stale local NIRI_SOCKET, then execs the unmodified
native start-umbriel. A missing HM profile fails clearly rather than starting a
partially configured trial. It never evaluates arbitrary pasted commands or
changes the user's default shell.

The XKB root must be present **before** Umbriel loads/validates its keyboard config;
putting it only in [environment] is too late for initial keymap validation. The
config also publishes it and clears NIRI_SOCKET for session services. Model/layout/
options match the configured pc104/us-umlauts/lv3:ralt_switch setup.

The upstream unit is **Type=notify**, and the same package's binary provides the
readiness notification, so keep that pairing. start-umbriel imports the loaded
session environment into the user systemd manager before
`systemctl --user --wait start umbriel.service`, then tears the session down via
umbriel-shutdown.target. Reviewed startup publishes display/IPC/configured
environment, then starts umbriel-session.target/graphical targets. Keep that
native lifecycle and verify it live; offline checks do not prove portal readiness
or session cleanup.

Noctalia and existing user services start through graphical-session.target, not
another `noctalia` autostart. Umbriel owns Xwayland through its packaged integration;
do not launch the Niri xwayland-satellite startup alongside it. The sole configured
startup command preserves the existing 0.5s Framework pw-loopback initialization,
with absolute executable paths. Audio keep-alive/watcher, brightness/DDC helper,
tuned, root fingerprint/lid management, guarded suspend and native idle stay intact.
No lid hook, second idle scheduler or power-key binding is added; logind keeps its
policy. The power-button backlog remains deferred, not fixed by this trial.

## Appearance, palette and overview

- Scrolling layout, 12px gaps, half-width initial windows, 75/50/25% extent presets,
  4px borders, 16px corners, no compositor blur/shadow added.
- Internal output scale 1.4 and DP-3 4K/120 scale 1.25 retained declaratively, VRR
  always, vertical workspace axis. At least nine dynamic workspaces are reserved on
  those outputs for existing numeric shortcuts; this can show more empty previews
  than Niri's dynamic list. No output operation was exercised by the agent.
- Overview zoom 0.5, no workspace wallpaper mirroring or background blur, and
  transparent workspace/tint colors. Native Noctalia remains the sole wallpaper
  renderer with its extra backdrop disabled. Actual visual parity needs user review.
- Reuse the maintained Noctalia Umbriel template verbatim as a native user entry.
  Do **not** run its apply.sh: it can copy over the managed main TOML. The declarative
  main includes a separate writable optional noctalia.toml, prepared without writing
  through links. Main layout/alpha choices override included colors intentionally.
- The existing overview watcher now selects Niri or Umbriel by the active desktop,
  not a stale other-compositor socket. Niri's EventStream is unchanged; Umbriel uses
  its overview subscription and initial snapshot without half-closing that socket.
  Both hide panels/bar before initial state and close orphaned panels on exit.
- Bar capsules, text, fonts, clock, spacing and widgets are unchanged. Native
  overview-type-to-launch is off in both compositors. Topbar UI is the later task.

## Bindings and explicit differences

All existing declared Niri key positions are mapped (wheel names translated).
Alt+Tab is additionally registered for the native Noctalia window-switcher hold
command; it was absent from the mapped Niri bindings, not an unsupported Umbriel
feature. Hold Alt, press Tab to cycle and release Alt to select. Once open, Noctalia
handles Shift+Tab/backward navigation and Escape/cancel. Pinned IPC accepts hold,
not a fabricated reverse argument, so no separate initial Alt+Shift+Tab command
is promised. Repeat is false and no locked-session exemption is granted.
Terminal/launcher, close, overview, focus/move/output/workspace, tabbed/floating,
size presets, lock, guarded suspend, media/5%-volume and brightness helpers retain
corresponding actions. Plain F1–F12 are not intercepted. Mod+Shift+D uses Umbriel's
own output-toggle instead of invoking the Niri-only helper.

This is not complete semantic parity:

| Key | Trial difference |
|---|---|
| Mod+Ctrl+C | Centers focused column, not all visible columns |
| Mod+Ctrl+R | Sets secondary extent to 0.5, not Niri's automatic-height reset |
| Mod+Period | Uses consume-or-expel-right, not unconditional expel-only |
| Mod+Ctrl+F | Toggles maximize-to-edges, not Niri's expand-to-available-width |
| Shift+Print | Region selection, not a focused-window-only screenshot |
| Print / Ctrl+Print | Native Noctalia region/fullscreen capture rather than Niri's UI |
| Wheel workspace/move bindings | Native Umbriel cadence; Niri's 150ms cooldown is not copied |

Mod+Shift+Ctrl+Q keeps the explicit unconfirmed session-exit shortcut; ordinary
quit bindings use the compositor's confirmation. No locked-session exit exemption
or additional locked-key capability is granted.

## Portal and security boundaries

Umbriel's portal advertises ScreenCast and Screenshot; its per-desktop routing uses
those interfaces while GTK handles Settings/default interfaces. Niri's portal config
is unchanged. Do not restart live portals as an agent to force an appearance of
success; verify the new native session after user entry.

All six current PAM files, native locker/idle configuration, logind settings and
Niri's generated config are unchanged; the latter also compared identical to the
currently deployed file. Native source review found three-second lock-surface
handoff, opaque fallback blank, presented-frame confirmation and retained locked
state after client destruction. This is source evidence, not a real lock/rendering
or suspend test under Umbriel. Preserve password/TTY recovery and the previous boot
and Niri sessions. Never kill/restart a locked Noctalia as recovery.

The [reader/output/power backlog](noctalia-backlog.md) stays deferred. Basic behavior
on a **new compositor** must still be described honestly; existing Niri acceptance
does not certify Umbriel. Don't use the trial for sensitive unattended work before
normal lock behavior has been user-checked.

## Validation completed

Full Framework build and all **19 x86_64-linux checks** pass after the flake
switch, including `cache-trust` and the Umbriel trial. These include:

- 177 Noctalia tests, including five new compositor-selection/Umbriel overview probes.
- Eleven Umbriel probes: actual flake-binary config validation, native renderer in
  both modes, immutable main preservation, malformed optional data rejection,
  binding/policy checks, dual session entries, private fake-launcher
  HM/Nushell/XKB environment tests (including the real generated HM profile with
  unset optional variables), provider/routing inspection and the native
  held-switcher binding. No Wayland,
  D-Bus, real switcher/focus operation or device connection.
- Existing eight Greeter and 19 mocked suspend probes; no authentication performed.
- Niri/default/PAM/bar/idle/lock/logind invariance and constant Umbriel main config
  across light/dark specialisations; no runtime output managed as a store file.

No compositor session was launched by the agent. Visuals, input handling,
lock/unlock, actual portals, power and return-to-Niri behavior are not established
by these checks.

### Initial user session and Alt+Tab follow-up

The user rebooted into Umbriel and reported it works well so far, except Alt+Tab.
Read-only inspection found XDG_CURRENT_DESKTOP=umbriel, a valid UMBRIEL_SOCKET and
empty NIRI_SOCKET. Umbriel started at 17:02:37; native Noctalia and the overview
watcher at 17:02:38. All remained active with zero restarts, and the watcher logged
successful native visibility calls during user interaction. Accept the observed
session startup/basic smoke only; don't infer detailed visuals, lock, capture,
hardware, inhibitor or fallback-session acceptance.

The missing Alt+Tab binding is now added using Noctalia's documented native
window-switcher hold integration, verified against pinned 5.3 source. All 19 checks
and 11 Umbriel probes pass. The user applied the binding and confirmed Alt+Tab works.
Read-only inspection found the installed native window-switcher hold binding with
repeat=false, valid config reloads at 18:58:43/51, and Umbriel/Noctalia/overview still
active with their original 17:02 start times and zero restarts. Accept the reported
normal shortcut behavior, not unreported individual reverse/cancel/output cases or
unrelated runtime gates. The agent never opens the switcher, changes focus, restarts
the compositor or forces a reload. Niri bindings/default stay unchanged.

### Fan/GPU observation — diagnosis, not a tuning change

After the initial trial the user reported fan noise despite low CPU load. A quiet
16.21s read-only sample found 2.31% whole-system CPU busy and 18–19% GPU busy, with
GPU edge 64–65°C, CPU Tctl about 66–68°C and fan roughly 3,800–4,000 RPM. Deduplicated
AMDGPU fdinfo gfx-engine deltas attributed about 11.37% busy time to Zen, 5.93% to
two Ghostty clients, 1.08% to Umbriel and 0.08% to Noctalia. These are engine-time
percentages, not percentages of total power. The internal preferred mode was
2880×1920/120Hz; platform profile balanced, EPP balance_performance, AC connected.
No kernel GPU fault/reset/timeout was found in the inspected window.

This identifies browser/terminal rendering as the main **direct** graphics work in
that sample, not the cause of a change versus Niri. Compositor frame pacing could
still affect client work; a like-for-like Niri comparison has not been done.
APU driver power readings must not be called discrete
GPU-only wattage. No fan, clock, power, render, playback, window/focus or session
state was changed by the agent. Performance concern remains open; no tuning fix.

The user then left Zen on about:about. A second 16.30s sample measured Zen's gfx
engine delta at 0.00%, total GPU busy 7–8%, Ghostty clients 6.79%, Umbriel 1.17% and
Noctalia 0.11%. Whole CPU busy was 1.91%, GPU edge about 59–61°C and fan about
2,960–2,990 RPM. Under these conditions Zen is not continuously rendering its chrome;
the prior activity is associated with its previous page/browser workload, whose
specific cause is not yet identified. No history, cookies, other tab contents or
URLs were inspected. Managed chrome imports are static palette CSS; imported theme
contains some backdrop blur, but no keyframe/animation rule was found by the focused
scan. This does not prove an arbitrary prior page or extension innocent/at fault.

The user identified the previous page as https://noctalia.dev/. Public production
HTML/JS inspection found its full-viewport plexus-canvas: a 2D canvas with 100 moving
particles/connections, a persistent requestAnimationFrame loop and about 30fps draw
throttling, plus high-DPI backing resolution (devicePixelRatio capped at 2). It
redraws while visible even without pointer motion, skips drawing when the document
is hidden, and skips initializing the effect if prefers-reduced-motion is reduce
at mount. A reload is needed after changing that preference. This concrete page
animation fits the measured Zen gfx drop from 11.37% to 0.00%; don't confuse the
marketing website with the installed Noctalia shell's tiny measured GPU time or
claim an Umbriel driver fault. Exact per-effect attribution is not profiled. No
browser/desktop preference was changed. Reviewed asset on 2026-10-23:
https://noctalia.dev/_app/immutable/nodes/0.3_lnoJU4.js.

The user later reported fan activity with Gmail. A new 16.26s foreground sample
found Zen effectively idle, total GPU busy 7–9%, Ghostty hosting Pi at 6.15% plus
btop's Ghostty at 0.63%, Umbriel 1.12% and Noctalia 0.09%. Thus the homepage animation
explained an increment, not the persistent baseline; the earlier attribution must
not be read as exonerating compositor-induced client activity.

Foreground tool calls animate the Pi UI, so a read-only background sampler was
scheduled after the response completed. The user's 60s hands-off interval yielded
16.31s of quiet sampling: total GPU busy 2%, Pi's Ghostty 0.59%, btop's Ghostty 0.84%,
Umbriel 0.34%, Noctalia 0.16%; whole CPU busy 0.99%. A deliberate active-tool repeat
returned 8–9% total, Pi's Ghostty 6.25%, btop's 0.63%, Umbriel 1.16% and Noctalia
0.11%. Pi's CPU rose from 1.47% to 16.9% of one core, with aggregate process write
counters rising from 144 to 100,928 bytes (not TTY-specific counters). No terminal
contents were read. Ghostty has no configured custom shader/animation override.

This implicates active Pi/TUI redraw work rather than a constant 7% idle-terminal
load. It does not establish whether active rendering is efficient under Umbriel or
rule out fractional-scale/frame-pacing costs. A matched Niri comparison has not
been done; do not tune clocks, fan policy, acceleration or refresh rate blindly.

### Upstream idle-redraw and explicit-sync fixes now included

The previous nixpkgs pin (`0-unstable-2026-10-16`, `5cea311`) predated upstream
fixes `5b66788` (avoid redraws for unchanged surface commits), `e65cc65` (suspend
hidden windows and stop their frame callbacks) and `a2462e71` (latch explicit-sync
commits until the acquire point signals; frame pacing with VRR and direct
scanout). The flake pin (`814d761`) includes all three. Upstream issue #473
documents idle CPU/GPU work scaling with output refresh rate; the fix reduced one
reported idle case to roughly 1%.

This is a compositor issue, not a tuned or power-profile failure. The panel itself
supports VRR from 30–120 Hz, and Umbriel already reports adaptive sync enabled.
Do not disable VRR or tune clocks to compensate. Verify idle GPU/battery behavior
in a user session before treating the trial's power behavior as resolved; offline
checks and the local build say nothing about runtime frame pacing. Until measured
otherwise Niri remains the lower-power session option.

## Owner disposition: keep both

The owner chose to retain both Niri and Umbriel and experiment with performance/
behavior differences when convenient. This accepts coexistence, not a permanent
replacement or blanket Umbriel runtime/security/performance approval. Niri remains
the configured Greeter default; either session can be selected deliberately after
saving work and logging out. No default switch, uninstall or forced benchmark.
Shared topbar UI work may be discussed next without choosing a winner, preserving
both overview adapters and current behavior unless the owner requests a change.

Track optional comparison in [backlog NOC-04](noctalia-backlog.md). Do not repeatedly
ask for an A/B run as a migration gate. Alt+Tab was subsequently installed by the
user and confirmed working; passive config/service checks corroborate installation
without a compositor restart. This does not close unrelated runtime/performance gates.
No rebuild is required merely to continue using the two already installed sessions.

## User-only first trial / later session selection

1. Save work and keep the known TTY/password route and previous generation. Run
   bare `rebuild` to stage boot, then reboot yourself when convenient. Do not use
   `rebuild boot`; this project's helper only special-cases `switch`.
2. In Noctalia Greeter, deliberately select **Umbriel**, then log in normally. Niri
   remains the default; its entry has not been removed or repointed.
3. First check a terminal (Mod+G), launcher (Mod+Space), window movement, overview
   (Mod+O), bar visibility and wallpaper/previews. Do not trigger hardware/sleep/
   authentication actions merely to satisfy the backlog.
4. Report basic behavior or nonsensitive errors. Then separately choose a normal
   user-operated lock/unlock check; the agent never initiates it. Portal/input/power
   acceptance can be staged, not assumed from a successful launch.
5. To leave a working unlocked trial, use Mod+Shift+Ctrl+Q (ends the session and its
   apps), or a normal confirmed session exit, then choose **Niri** in the Greeter.
   Save work first. If the trial is locked or unresponsive, use the established TTY/
   previous-generation recovery rather than blindly restarting the locker/compositor.

Do not select Umbriel by default, remove Niri, retire fallback/auth, redesign the bar,
clear GUI settings or mark the trial accepted until user results are recorded.
