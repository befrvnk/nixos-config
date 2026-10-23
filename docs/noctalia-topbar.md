# Noctalia continuous floating topbar

Status: **continuous bar/motion and placement accepted** (783f890, 5665d8d).
The configuration-only visual polish below is also user-accepted (2026-10-23),
corroborated by installed settings and healthy services; scope limits remain below.

The owner requested one continuous bar rather than individual widget islands and
an animation originating at the display edge, while keeping one floating gap.

## Declarative style

- One opaque native Surface-role background; widget capsule backgrounds disabled.
- Keep top and side margins at **16 logical pixels** and bar thickness at 34.
- Horizontal content padding is 12px, replacing the outer padding supplied by the
  former capsules. This is main-axis padding, not another vertical/top gap.
- Widget order, neutral text, fonts/font scale and clock format remain. Notifications
  stay after clock in center. Widget spacing is now 12px (previously 16px).
  No widget, keybinding, wallpaper or OSD functionality is removed.
- Strict overview-only watcher remains active for Niri and Umbriel; pointer/smart
  auto-hide, workspace peek and reserved space remain disabled.
- No blur/shadow, extra effect, timer or continuous animation cadence change is
  added. Only the explicit bar-exit duration/curve is refined as described below.

Relevant GUI main-bar and per-widget capsule overrides were inspected read-only;
none masked these fields. settings.toml was not cleared or modified.

## Native edge-slide fix

Pinned V5.3 only folded margin_edge into the surface when auto-hide was enabled.
With explicit IPC visibility and auto-hide off, the layer surface itself started
16px from the display edge. Sliding content was therefore clipped at that inset,
not at the physical edge. Enabling pointer auto-hide to obtain its geometry would
violate overview-only behavior and is not an acceptable workaround.

bar-ipc-edge-slide.patch folds the positive anchored edge gap inside the surface
for explicit IPC animation too. The native visual rectangle still rests at 16px,
but the surface starts at 0; content travels through the transparent gutter while
sliding. Non-auto-hide input remains limited to the content body (no pointer
hot-strip), and hidden input behavior is unchanged. No visibility-policy predicates
or overview watcher commands are changed.

Reservation math is updated alongside surface placement: exclusive zone plus layer
margin preserves the same total edge distance, so attached panels/other bars don't
lose or duplicate the gap. Existing pointer/smart auto-hide and zero-gap geometry
remain unchanged. The patch handles all four anchored positions and shadow bleed,
not a hard-coded top-bar name or monitor workaround. It applies with --fuzz=0 and
no offsets against the pinned source; the PAM and suspend-policy patches remain.

## Checks

- Rebuilt the actual patched Noctalia package, full Framework system and all 21
  Linux checks. Native config validation and all 181 Noctalia tests pass, alongside
  existing 11 Umbriel, 8 Greeter and 19 mocked suspend probes.
- New offline C++ probe extracts the exact original/patched native geometry functions
  and input value type, linking native shadow calculations; no reimplemented geometry
  model or GUI/compositor/device is used. Its 432 cases compare four positions,
  auto-hide modes, gaps, shadow states/directions and reservation settings.
- Probe checks unchanged resting positions/sizes and panel reservation, unchanged
  auto-hide/zero-gap geometry, and manual input excluding the transparent gutter.
  The requested top-bar case has surface origin 0, height 50, body Y=16, body height
  34 and zero exclusive zone; a partially revealed frame intersects display edge 0
  before settling at the one floating gap. Pointer-reveal policy stays false.
- The same probe compiles the actual original/patched explicit-IPC animate-call
  duration/easing expressions and links native applyEasing. Entrance stays 200ms
  ease-out; exit is 100ms EaseOutCubic instead of 200ms EaseInQuad. For the requested
  geometry native bar ink is offscreen by 60ms **after its own exit starts**, versus
  still visible with the old curve. This is not a compositor/IPC latency guarantee.
- Four style probes preserve widgets/typography/order and enforce the continuous
  background, one margin, no pointer reveal/strut and inclusion of the strict patch.
- Formatting/lint pass. Build/test success is not observed animation, hit-testing,
  panel placement, fractional-scale or visual acceptance on either compositor.

## Live feedback: exit motion needs refinement

The user applied the continuous bar. Read-only config confirms the requested style;
Umbriel retained its 17:02 start time while Noctalia/overview restarted at 19:58:27
for the package change. The user reports exit is too slow and overlaps returning
overview windows. Pinned Umbriel reports overview closed at the start of its return
animation, not the end. Native explicit-IPC bar hide still uses 200ms EaseInQuad,
which accelerates slowly; the watcher also closes panels before issuing bar-hide.

The owner requested motion first, visual refinements later. The prepared patch now
changes only the manual explicit-IPC animate call: visible keeps native animNormal
(200ms), hidden uses animFast (100ms), both EaseOutCubic. Auto-hide's separate path,
all other animations, compositor timing, overview watcher/panel-close command order,
resting gap and widget style remain unchanged. The user subsequently applied it and confirmed the animation timing is good and
likes the current enhancements. Read-only config confirmed the continuous style;
Noctalia/overview restarted at 20:24:05 for the package update while Umbriel retained
its original 17:02 start time. Accept reported bar/motion behavior, not every popup
anchor: the user then reported tray menus appearing at the bar's left/bottom rather
than below the clicked icon, to investigate separately. A shorter asynchronous slide
is not a strict no-overlap synchronization guarantee. Do not enable reserved space,
move the bar behind windows, or slow the compositor to disguise the symptom.

## Center notifications and tray click-anchor follow-up — accepted

The accepted continuous-bar/motion checkpoint is signed as 783f890. The owner then
requested notifications in the center and tray right-click menus below their icon.

Notifications move from end to center: weather, clock, notifications. The clock
retains anchor=true; other widget order, popup/toast policy and typography remain.

Pinned TrayMenu re-reads global pointer coordinates when creating the DBusmenu
popup. WaylandSeat queues pointer events, but a later leave in the same frame can
clear hasPointerPosition while leaving the parent surface known. Dispatching the
click then reaches a `(0,0)` fallback, consistent with a left-edge menu.
tray-menu-click-anchor.patch passes PointerData.sceneX/sceneY (already logical,
parent-surface-local) through the service callback into the menu. The immutable
click point is captured before menu-open/layout bus calls and preferred over later
pointer state. It is rounded once to the positioner's integer coordinate; no output
origin, bar margin or DPI scale is added again. Closing clears the captured point.
Legacy calls without an explicit point retain the previous pointer fallback; the
application-owned ContextMenu path, parent/serial/grab handling, native constraint
adjustments, menu actions and bus/Polkit permissions are unchanged.

A new offline native-code probe reproduces the old zero anchor after pointer leave
and verifies preservation after leave/later motion, valid zero clicks, fractional
rounding and legacy fallbacks. It compiles the actual original/patched selection
blocks with fake pointer state and guards the captured-event callback wiring. The
full package build checks public call-site types. No menu, Wayland/bus connection,
focus change or input injection is performed by the agent. Static reproduction is
not proof that this is the only cause of the user's observed placement: live
parent/compositor positioning still needs user confirmation, including any app
that supplies its own menu.

Full Framework build and all 21 Linux checks pass, including 180 Noctalia tests,
the native tray-anchor repro/captured-click probe, 432 geometry/timing cases and
existing Umbriel/Greeter/suspend probes. All four native patches apply strictly;
no dependency/lock/cache, PAM, compositor, animation-speed or visibility-policy
change is bundled into placement. Static checks are not live popup placement proof.

The user applied the follow-up and confirmed it works. Passive inspection found
center=[weather,clock,notifications], the bell removed from end and clock anchor
still true. Native/overview were active with zero restarts from 21:06:06/07;
Umbriel retained its original 17:02:37 start time. No tray/popup errors appeared in
the focused recent native log window. The agent never opened a menu or moved focus.
Accept the user-observed bell/menu placement in this session, not all apps, drawer/
submenu/output cases or Niri-specific runtime coverage. Application-owned menus and
other unperformed cases are not certified by this success.

For future placement changes, rebuild switch only while unlocked (package changed)
and user-check the bell/menu anchor. Report any app that still misplaces its own
menu; don't clear settings or restart locked services.

## Visual polish — configuration-only; user appearance accepted

After motion and tray/bell placement passed, the owner requested the deferred
refinements. Native settings now select one outline-role 1px inside border, uniform
16px corners and 12px widget spacing. The radius key seeds all four corners; no
per-corner GUI override was found. The single 16px floating/side gaps, 12px inner
padding, 34px height, full Surface background and strict overview-only policy stay.

Pinned sysmon provides label_min_width, so CPU and RAM values reserve at least 48px
and temperature at least 56px. These accommodate ordinary percentage/temperature
text at the retained mono font scale without setting a maximum or clipping values.
This reduces routine value-width jitter, not every possible width change. Icons,
units, sampling cadence, neutral highlighting and tooltips remain; network/Bluetooth
labels are not shortened or hidden and the centered clock retains its anchor.

No new native patch, dependency, animation, blur/shadow, poller, hardware or permission
change is needed. All four existing patches, 200/100ms motion and tray click-anchor
fix stay. Build/offline checks pass: all 21 Linux checks, 181 Noctalia tests, 432
native geometry cases (including the requested 16px-corner case), native exit timing,
tray anchor repro and existing Umbriel/Greeter/suspend checks. Four style probes now
guard outline/radius/spacing/numeric minima along with all preserved behavior.
None of these checks proves actual appearance, text widths or popup usability.

The user applied it and confirmed it looks good. Passive inspection found the 1px
outline, radius=16, spacing=12, value minima=48/48/56, unchanged 16px top/side gaps,
center notification group and no auto-hide/strut. Native/overview were active with
zero restarts from 21:24:35/36; Umbriel retained its original 17:02:37 start time.
Accept the reported appearance in this session, not extreme values, every font/
scale/output or unrelated performance/security coverage. No bar/focus/session or
hardware action was performed by the agent.

For future changes, rebuild switch only while unlocked and inspect appearance/
popup behavior. Further refinements need separate owner direction; do not trade
off visibility/recovery/performance policy.

## User-only trial

While **unlocked**, run rebuild switch. The package changed, so Noctalia may restart
as part of user activation; never apply/restart it while locked. The compositor
itself is not being replaced or restarted by this change. Save work as usual.

Open/close overview and check:

1. One connected background, not individual widget islands.
2. Entry still slides from the physical top edge into one floating gap. Exit
   retracts promptly and no longer visibly lingers over returning overview windows.
3. Side insets, widgets/text/clock, transparent previews and overview-only visibility
   remain usable. Try an ordinary widget popup to check its anchor, then close it.

Report appearance/behavior only. The agent never shows/hides the live bar to test,
changes focus, restarts services, activates a generation, locks or authenticates.
Niri remains the configured default; the user may inspect both sessions when useful,
not as a forced switch. Existing backlogged security/performance work stays deferred.
