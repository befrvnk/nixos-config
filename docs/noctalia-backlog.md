# Noctalia deferred backlog

**Owner decision: 2026-10-23.** These follow-ups are low priority and deferred until
encountered in normal use or explicitly requested. They are not the immediate next
steps and do not block ordinary consolidation/cleanup that preserves existing
security and recovery behavior. Do not repeatedly ask the user to run these tests
just to advance the migration.

Deferred means **not tested/resolved**, not passed. No runtime policy changes are
implied. Keep the native PAM, TTY/password recovery and installed fallback files;
fallback/auth retirement still needs its own explicit review. If an actual unlock
failure or uncovered desktop is observed, reassess priority rather than treating an
active security problem as routine backlog.

## NOC-01: Password recovery with the fingerprint reader unavailable

- **Status:** Deferred; normal password and fingerprint unlock passed, but genuine
  reader-unavailable password recovery has not been user-tested.
- **Revisit when:** The reader is actually unavailable/unresponsive, password fallback
  has a problem, or the user requests this recovery test.
- **Scope:** Confirm password input/unlock and preserve the established TTY/password
  route. Do not manufacture a reader outage merely to clear this item. Agents must
  not authenticate, stop/claim/scan the reader, or restart a locked Noctalia.

## NOC-02: External-output, reconnect and resume coverage

- **Status:** Deferred; current internal-display observations do not certify every
  output, reconnect/hotplug, resume rendering or no-desktop-flash behavior.
- **Revisit when:** Using an external monitor/dock, encountering a reconnect/rendering
  issue, or explicitly requesting multi-output validation.
- **Scope:** User-observe lock coverage and recovery on each relevant output. Include
  native wallpaper/backdrop placement and the independent wallpaper-pair policy
  when relevant; shell startup/mode switching passed, but fresh-OS-boot/external
  visual coverage must not be inferred from that. Preserve the single native layer
  and transparent overview previews; do not restart a locked shell for diagnosis.

## NOC-03: Combined power-button/fingerprint-sensor wake interaction

- **Status:** Deferred, unresolved. Earlier combined-button/sensor attempts resumed
  quickly; keyboard-initiated sleep and later lid tests worked. Generic ACPI IRQ 9
  did not identify the wake source or establish fingerprint causality.
- **Revisit when:** The behavior recurs or the user needs this power-button path.
- **Scope:** User-operated, one-variable-at-a-time observation with saved work and
  timestamps; compare kernel/logind/native logs. Do not disable devices, fingerprint
  authentication, change wake/firmware/kernel policy, or bypass inhibitors on the
  strength of the old wake IRQ alone.

## NOC-04: Niri/Umbriel rendering and thermal comparison (user-led)

- **Status:** The owner chose to keep both installed/selectable and experiment when
  convenient. Niri remains the default. No mandatory benchmark or immediate winner.
- **Evidence limit:** Foreground Pi/tool UI drove its Ghostty client to about 6.25%
  gfx-engine busy time; a quiet background sample reduced that client to 0.59% and
  total GPU busy to 2%. A website animation added Zen load, but Gmail was effectively
  idle. This does not establish normal rendering efficiency or exonerate compositor
  frame pacing. See [recorded observations](umbriel-trial.md#fangpu-observation--diagnosis-not-a-tuning-change).
- **Revisit when:** The owner reports differences or requests diagnosis/optimization.
  A useful comparison keeps workload, window sizes, refresh/scale and power state
  comparable, without the agent's foreground UI contaminating the quiet sample.
- **Scope:** Read-only telemetry first. No agent session switch or implicit clock,
  fan, refresh, acceleration, power or application/playback change. This is not a
  blocker for ordinary use or separately requested shared topbar UI work.

## Already verified — not backlog work

Independent full-duration Caffeine and Audio Playback idle suppression, the guarded
manual suspend veto with audio held, and both inhibitor releases passed on the
updated stack. See [inhibition evidence and recovery boundaries](noctalia-lockscreen-migration.md#updated-stack-extended-inhibition-validation-2026-10-23).

The independent native wallpaper startup/mode policy is accepted in
[the wallpaper guide](noctalia-niri-overview.md#independent-native-wallpaper-pair-policy-startupmode-accepted).

Implementation history and ordinary cleanup planning remain in the
[consolidation plan](noctalia-consolidation-plan.md). This backlog does not downgrade
unrelated cache-provenance/security follow-ups or authorize automatic fallback,
bridge, specialisation or policy removal.
