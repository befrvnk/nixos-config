# Noctalia continuous floating topbar

Status: **continuous floating bar and fast exit user-accepted** (2026-10-23).
Tray context-menu anchoring is a reported follow-up, not included in that acceptance.

The owner requested one continuous bar rather than individual widget islands and
an animation originating at the display edge, while keeping one floating gap.

## Declarative style

- One opaque native Surface-role background; widget capsule backgrounds disabled.
- Keep top and side margins at **16 logical pixels** and bar thickness at 34.
- Horizontal content padding is 12px, replacing the outer padding supplied by the
  former capsules. This is main-axis padding, not another vertical/top gap.
- Widget order, 16px widget spacing, neutral text, fonts/font scale and clock format
  remain. No widget, keybinding, wallpaper or OSD functionality is removed.
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

- Rebuilt the actual patched Noctalia package, full Framework system and all 20
  Linux checks. Native config validation and all 180 Noctalia tests pass, alongside
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
- Three style probes preserve widgets/typography/order and enforce the continuous
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

## Later visual refinements — not applied in the motion step

After motion acceptance, revisit the proposed quiet single outline, 16px corner
radius, 12px widget spacing and stable dynamic labels where native options permit.
Widget spacing currently stays 16px and no outline/radius override is introduced;
style tests guard those boundaries. No widget removal or typography change is implied.

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
