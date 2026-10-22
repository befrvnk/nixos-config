# Native Noctalia lock-screen migration

This is a security-sensitive, staged migration from swaylock. Native Noctalia is
pinned at V5.3.0. The agent must not lock/suspend, enter/test passwords, use the
fingerprint reader, restart a locked session, or activate the system configuration.

The subsequent [origin rebase validation](noctalia-origin-rebase.md) covers the newer
dependency pins and replayed checkpoint hashes. Live observations below predate
activation of that updated stack; do not treat them as fresh runtime acceptance.

## Stage 1: password authentication preflight (accepted)

During stage 1, **swaylock and all existing routes remained active and native
locking stayed disabled**. Stage 2 password/fingerprint unlock was accepted. Stage 3's
swayidle-based trial was activated; keyboard suspend and lid sleep/wake passed, but
full automatic suspend exposed a missing-command failure. The native-idle replacement
in stage 3b below is activated; automatic sleep/key-wake and basic inhibitor cycles
are verified. Extended inhibition, reader/output checks and the separate power-button
interaction are still open.

The pinned native code hardcodes the PAM service `login`. This machine's login
stack contains fingerprint and lid-check rules, whereas Noctalia operates fprintd
directly over D-Bus. Do not change TTY/login authentication for the locker. The
source's old comment claims fingerprint PAM filtering, but its implementation
calls pam_start directly; no such filtering was found in the reviewed code.

A small, exact-context package patch changes only the lock screen's selected PAM
service to `noctalia` and corrects that comment. It does not replace the authenticator
or add an environment-configurable service. Patching uses --fuzz=0 so source drift
fails the build. Review/remove the patch if a future upstream release supports a
dedicated service natively.

`modules/services/noctalia-auth.nix` adds a dedicated stack:

- auth required pam_unix
- account required pam_unix

There is no nullok, pam_permit, pam_fprintd, login include or keyring/session mutation
in this stack. Fingerprint will later use Noctalia's native path, separately from
password PAM. Native account-check behavior and fingerprint semantics must be
reviewed before claiming equivalence to swaylock's PAM path.

The generated login/swaylock/sudo/greetd/polkit-1 PAM files were compared to deployed
files and are byte-for-byte unchanged. Saved Noctalia lock overrides were checked
and none mask the disabled native lock screen. The new checker enforces the exact
password stack and existing lock/login routes during this stage.

### Manual preflight

The user activated stage one and confirmed that the correct password authenticates
and an incorrect password fails. This validates the dedicated password PAM path
only; native screen/fingerprint/lock protocol/suspend behavior are not yet tested.

Apply the prepared configuration yourself:

```sh
rebuild switch
```

Then authenticate without locking:

```sh
nix shell --accept-flake-config nixpkgs#pamtester --command pamtester noctalia frank authenticate
```

Enter your password privately in that local terminal. Do not send it to the agent.
A valid password must succeed. Run once more and verify one deliberately invalid
password is rejected; do not repeat failures or treat a successful build as an
authentication test. Report only success/failure and any nonsensitive error text.

If the service is missing, a valid password fails, or an invalid one succeeds,
stop here. Keep the native screen disabled and investigate before any cutover.
This command tests password PAM, not the native screen, fingerprint or rendering.

## Stage 2: manual native-screen trial (password/fingerprint accepted)

The password preflight passed. The user then activated this stage and confirmed
both native password and fingerprint unlock work. Live settings/manual bindings
and retained automatic swaylock routes were inspected; native services remain active.
Wrong-password UI rejection, multi-output coverage and sleep recovery are not yet
separately confirmed.

`noctalia/lockscreen.nix` enables the native screen
with no grace, no empty-password submission, no desktop capture, no transitions and
all outputs protected. The manual Mod+Shift+X shortcut and native logind Lock handling
use Noctalia. The duplicate swayidle logind `lock` event is removed.

**Idle locking at 300 seconds and pre-sleep locking still use swaylock.** Native
lock_before_suspend is false for this trial, so swayidle retains that responsibility.
The existing 305-second screen power and 310-second safe-suspend behavior are unchanged;
native idle behaviors remain disabled. This is not yet the automatic-route cutover.
If idle lock fires during an already-active native lock, a second locker may fail to
acquire the protocol; the first lock remains secure. Test promptly and don't test
sleep/lid behavior in this checkpoint.

### Fingerprint review boundary

Native fingerprint uses the fprintd D-Bus service, claims with an empty username
(current caller per the [fprintd API](https://fprint.freedesktop.org/fprintd-dev/Device.html)),
and verifies against that user's enrolled fingers. The reviewed code releases the
claim when stopped, pauses verification across sleep and stops the reader before
password PAM. Missing/failed reader operation leaves password authentication available.

A native fingerprint match directly unlocks; it does not run password PAM/account
checks. This is not identical to the previous PAM-based fingerprint path, especially
for expired/restricted accounts. The existing root lid/fprintd management and other
PAM services are unchanged. No fingerprint or account-policy parity is claimed by
configuration tests; don't broaden deployment without reviewing those requirements.

### Before applying/testing

1. Save work and establish a working TTY/password login recovery route first.
2. Read the recovery boundary below. Do not rely on swaylock to unlock an already
   active native session lock, or on killing/restarting Noctalia as a recovery method.
3. Apply with `rebuild switch` only while the session is unlocked.
4. Use Mod+Shift+X (or `noctalia msg session lock`) yourself. First avoid touching the
   reader and verify password unlock, including one wrong-password rejection. Then
   lock again and test fingerprint. Confirm keyboard input/layout and every output
   is covered; the agent must not perform these actions.
5. If fingerprint is unavailable, test password fallback rather than stopping services.
   Report nonsensitive status/log messages only, never passwords or fingerprint data.

If recovery is needed, switch to the prevalidated TTY and investigate. Last-resort
termination of the graphical session/reboot loses unsaved work and is the user's
choice; identify the correct graphical session (not the recovery TTY). Restore the
stage-one configuration if necessary before starting another graphical session.

## Stage 3: swayidle-based automatic-route trial (historical; replacement prepared)

Manual password/fingerprint unlock passed. The prepared configuration enables native
lock_before_suspend and removes all swayidle logind lock/before-sleep listeners.
Noctalia owns lock-before-sleep with its logind delay inhibitor; the current limit
was read as five seconds. Lock animations remain disabled. This is the upstream
bounded-delay implementation, not an independently proven never-fail sleep guarantee.

Swayidle remains the sole inactivity timing source, preserving audio inhibition:

- 300s: native session lock
- 305s: native dpms-off, with dpms-on on activity
- 310s: safe-suspend --require-lock

The new idle-only guard resolves the session from XDG_SESSION_ID or the user's logind
Display session, requires a positive LockedHint, and fails closed on lookup errors,
missing session or absent/unknown hint. Existing high-level sleep-blocker checks
still run first; delay/weak locks remain logind's responsibility. The hint is a
conventional published state, not cryptographic proof of compositor readiness.
Manual safe-suspend keeps its previous behavior, with native PrepareForSleep handling
providing the lock. No --ignore-inhibitors behavior is introduced.

### Native suspend policy

Pinned V5's plain Suspend intentionally sets a skip-next-lock flag before launching
a detached power command. A later failure can leave that flag stale. A second small,
exact-context package patch makes it respect configured lock-before-suspend instead.
It doesn't change PAM/authentication or compositor protocol code.

The session panel's third entry is Lock and Suspend, not unlocked Suspend. All native
suspend backends are overridden with safe-suspend --require-lock, preserving blockers
and lock confirmation. Thus a plain native `session suspend` request while unlocked
fails closed rather than sleeping; use Lock and Suspend or the regular manual
safe-suspend key. The policy patch prevents a failed detached request from poisoning
later external sleep lock handling. These intentional policy differences must not
be removed by enabling a duplicate/old GUI override. A read-only audit found no
relevant lock or shell.session GUI overrides before activation; the rest of the
settings file was left untouched.

Swaylock and its PAM/static configuration remain installed for rollback, but no
default automatic route invokes it. Its remaining Stylix consumer is not retired
until this checkpoint is accepted. Root fprintd/lid/tuned/Caffeine policy is unchanged.

### First activation and timer-only inhibitor fix

The user activated stage three. Read-only inspection confirmed native Noctalia,
swayidle and overview services active, the intended 300/305/310s commands installed,
and Noctalia's sleep-delay inhibitor acquired. No automatic GUI behavior is accepted
yet. Inspection also found swayidle's `Failed to parse get BlockInhibited property`
warning: V1.9 only connects to logind when a non-timer event is configured. Removing
the last pre-sleep hook left its inhibitor query with no bus connection, so audio/
Caffeine idle inhibition was not reliable in that first activation.

A one-line exact-match swayidle package patch now connects to logind when timers
exist too. This restores property monitoring without dummy commands, lock listeners
or another sleep-delay inhibitor. The module installs only its configured package,
not an extra unpatched swayidle. Six static lock-policy tests include the timer-only
patch/no-dummy-hook regression; all 137 Noctalia tests, 19 mocked suspend tests and
full Framework build pass. The user activated the correction. Read-only inspection
confirmed the running swayidle executable matches the patched package, its system-bus
connection exists, and the BlockInhibited startup warning is absent. Native Noctalia,
swayidle and overview remain active; Noctalia's sleep-delay inhibitor remains held.
User-operated inhibitor/sleep trials and remaining idle checks are still pending:
successful startup and source policy/build checks are not live audio/Caffeine or
lock-before-sleep acceptance.

Historical pre-cutover swaylock logs also showed fingerprint PAM module-load errors.
This is not a native PAM failure and no authentication action was attempted, but
installed rollback files must not be mistaken for verified fingerprint recovery.
Keep the separately prevalidated TTY/password recovery path available.

After activating the corrected stage-three configuration, the user confirmed native
UI rejection of an incorrect password and successful correct-password unlock. This
closes the previously unconfirmed native UI negative-password check, but does not
prove idle/DPMS, suspend/lid, reader-unavailable fallback or multi-output coverage.

The user then reported idle blanking and a key press restoring the native lock
screen, rather than an unlocked desktop. Record that observed idle/wake-to-lock
behavior as accepted, without claiming exact timeout measurements or all-output
coverage. Read-only inspection found all three services active, native lock-confirmed
and unlock-requested log events, and the native sleep-delay inhibitor still held.
These observations do not independently establish an actual suspend/resume cycle.

### Suspend investigation (keyboard path accepted; power-button issue open)

The subsequent user-operated manual suspend trial did not stay asleep. Read-only
logs show three kernel s2idle entry/exit cycles at 12:13:07–09, 12:13:19–23 and
12:14:05–07 on 2026-10-22. Noctalia reported the session locked before releasing
its delay inhibitor each time, then reacquired the inhibitor on resume. No high-level
sleep blocker was present at inspection and CanSuspend returned yes. The request
reached kernel suspend; this is an immediate-resume investigation, not evidence that
the helper refused to request sleep. Those elapsed times include suspend preparation,
not measured sleep residency.

The last reported wake IRQ was 9 (ACPI SCI), which does not identify a specific
physical device. Only s2idle is advertised. No RTC wake alarm was set; the Goodix
USB device's wake permission was already disabled. Neither that setting nor normal
USB-reset logs proves or excludes a fingerprint-related interaction. Nearby fprintd
cleanup/stale-claim warnings are observations, not an established wake cause.

The same boot/kernel previously sustained overnight sleep before this automatic
cutover, so a migration interaction remains possible and must not be dismissed as
an unrelated hardware problem. Do not accept sustained suspend, remove rollback,
change kernel/wake-device policy or disable authentication based on these logs.
No suspend/authentication/device-state action was performed by the agent. Next
establish whether wake was spontaneous with keyboard/touchpad/sensor/lid untouched,
then isolate one variable at a time with user-operated trials.

The user clarified that power-button presses (also touching the fingerprint sensor)
preceded the first attempts, followed by lid-close tests with the screen still on.
Logind confirms the first two suspend requests came from Niri's power-key handler;
the third came from systemctl. This does not establish which device caused wake.

The two lid closes occurred 5s and 12s after the second resume and were reopened
within 20s. Live HoldoffTimeoutUSec is 30000000: logind deliberately holds off lid
events for 30s after resume to allow dock/output discovery. Docked was false at
inspection; normal/external-power lid policy is suspend and docked policy is ignore.
No lid-triggered suspend was logged in those short tests. This is consistent with
the holdoff, not evidence that lid handling must be rewritten. Preserve that policy.

Next isolate input: after saving work and settling after resume, the user can invoke
safe-suspend or Mod+Shift+S with the lid left open and keep hands away from keyboard,
touchpad and power/sensor for at least 20s. Record whether it resumes before further
input; only the user wakes it afterward. Do not disable fingerprint or device wake
permissions based solely on the combined-button suspicion.

The next user-operated Mod+Shift+S trial succeeded. Kernel logs show s2idle entry at
12:26:53 and resume at 12:29:23 (about 2m30s entry-to-exit, not an immediate return).
Native lock confirmation preceded delay release; the inhibitor was reacquired on
resume and an unlock request followed. All three user services remained active.
Accept sustained keyboard-initiated safe-suspend as reported, not the separate
power-button interaction, exact low-power residency, all-output rendering or a
specific unlock method. Fingerprint authentication was not disabled. Next test lid
closure after the post-resume holdoff; automatic 310s suspension and inhibitor
behavior remain separate acceptance items.

After the user reported completing the lid trial, read-only logs confirm lid-close
at 12:36:34 requested suspend, kernel s2idle entry at 12:36:35 and resume on lid-open
at 12:36:56. Native lock confirmation preceded delay release; the inhibitor was
reacquired on resume and an unlock request followed. All three services remain
active. The user subsequently confirmed the native lock screen appeared after
lid-open. Accept the logged lid-triggered sleep/wake and reported lock presentation
outside holdoff. Normal unlock on this particular trial was not separately stated;
do not infer a specific authentication method, no-flash behavior or all-output
coverage. The power-button interaction and automatic 310s suspend/inhibitor trials
remain separate open checks.

## Stage 3b: native idle cutover (automatic route and inhibitor integration verified)

The full idle trial locked at 12:49:46 and powered monitors off at 12:49:51, but
never requested sleep. The complete journal revealed `safe-suspend: command not found`
at 12:49:56. Swayidle's service PATH contained only Bash, unlike the working keyboard
session. This was a launcher failure, not another immediate kernel wake.

The shared `niri/safe-suspend-package.nix` now provides one explicit-PATH executable.
The keyboard shortcut and native power backend use its absolute store path; the
manual `safe-suspend` profile command remains available. Authentication, inhibitor
parsing, positive-lock-hint guard and systemctl invocation are unchanged.

The user approved replacing swayidle with native scheduling. `noctalia/idle.nix`
configures the built-in behaviors in canonical order:

| Idle time | Native action |
|---|---|
| 300s | lock |
| 305s | screen_off, with native activity-based monitor restoration |
| 310s | lock_and_suspend |

Pre-action fade is zero to avoid adding the default two seconds. Every locked_timeout
is zero, which uses the original timeout; the reviewed implementation retains timers
when locking doesn't change their effective duration. No custom idle commands or
resume controller are introduced. Native lock-and-suspend waits for the native lock
and invokes the configured absolute `safe-suspend --require-lock` power backend.
Noctalia still owns external logind Lock/PrepareForSleep and its delay inhibitor.

The reviewed native ScreenSaverService monitors logind BlockInhibited and feeds idle
blocks into IdleManager, preserving the existing audio watcher's idle:sleep blocks.
Native idle also respects screensaver/Wayland inhibition and Caffeine. Keep the audio
watcher, tuned, root fingerprint/lid policy, 30s lid holdoff and Lid Guard unchanged.
Source review is not live acceptance of every inhibitor interaction.

Swayidle is disabled, no user unit is generated, and its temporary package patch is
removed. Swaylock/PAM/style remain recovery-only until automatic acceptance. No
bridge, specialisation or fallback-auth cleanup is bundled into this change. A
read-only audit found no GUI idle or shell.session overrides; no settings were erased.

Eight policy/probe tests verify sole scheduler, native actions/order/timings, no extra
fade/reset timeout, retained secure lock/default/manual routes, empty-PATH command
resolution and actual configured-binary validation. Resolution probes do not run the
helper. All 139 Noctalia tests, 19 mocked suspend tests, auth/cache/theme checks,
format/lint and the full Framework build pass. No agent session/hardware action or
activation was performed. The user activated the cutover. Read-only inspection at
13:09 confirmed no swayidle unit/process, active Noctalia/overview services, native
registration of 300/305/310s behaviors, logind idle monitoring and native sleep-delay
inhibition. The deployed backend is the absolute guarded helper, fade/locked-timeout
values match, and GUI idle/session overrides remain empty. Extended inhibited-idle
validation remains pending; the power-button wake interaction remains
unresolved and must not be marked fixed.

The first native-idle trial now reached the kernel: native lock triggered at
13:14:05 (lock confirmed .875), screen-off at 13:14:10 and suspend at 13:14:15.
The absolute override launched, logind accepted the systemctl request and native
delay was released after locking. Kernel s2idle entry was 13:14:16; exit 13:14:29.
Native delay was reacquired, all three behavior resume callbacks ran and an unlock
request followed. No helper failure was found; Noctalia/overview remained active
and swayidle remained absent. This verifies the native action chain and working
backend. The interval is about 13s including preparation; the user explicitly
confirmed that their key press caused the wake. Accept the observed automatic
lock/monitor-off/suspend and stayed-asleep-until-key-wake path. This is not an
extended low-power residency test or proof of power-button/inhibitor behavior.

The user enabled Caffeine for a live integration probe. At 13:25:06 Noctalia
acquired a logind idle/block inhibitor labelled Caffeine; BlockInhibited included
idle and native logs reported inhibitor enabled via logind / systemd idle inhibit
active. Native services remained healthy. Accept acquisition and native detection,
not an unperformed full-duration idle-suppression trial. Next disable Caffeine by
user action before audio playback so its inhibitor cannot mask the audio probe.
Audio acquisition/native detection and sustained inhibited-idle behavior remain
separate checks. No agent inhibitor or hardware-state change was performed.

For the isolated audio probe the user disabled Caffeine and started playback.
Native logs show Caffeine release at 13:28:15 and a new systemd idle inhibit active
at 13:28:33. Read-only inspection found Audio Playback holding sleep:idle/block,
aggregate BlockInhibited containing both sleep and idle, and no Caffeine inhibitor.
The existing audio watcher, native shell and overview services were active; swayidle
remained absent. Accept independent audio acquisition/native recognition and
Caffeine release. Audio release after pause and extended timed idle suppression
remain untested; no actual suspend request was issued to challenge the blocker.

The user then paused playback. At 13:29:43 native logs reported systemd idle inhibit
released. Read-only inspection at 13:30 found neither Audio Playback nor Caffeine
holding idle/sleep blocks; aggregate BlockInhibited contained only Niri's expected
handle-power-key block. Native shell, overview and audio watcher remained active;
swayidle remained absent. Accept audio release and the basic Caffeine/audio
acquisition-recognition-release integration cycle. Do not convert those observations
into full-duration inhibited-idle or real suspend-block challenge acceptance.

Core native automatic scheduling/backend, keyboard/lid sleep paths and inhibitor
integration have observed evidence. Power-button wake behavior, extended inhibited
idle, reader-unavailable password fallback and external-output coverage remain
explicit follow-ups. Retain fallback files/style and the theme bridge; do not remove
them or silently label the whole security migration accepted. The user explicitly
authorized committing this checkpoint with the following follow-ups documented;
authorization does not turn unperformed tests into acceptance.

### Checkpoint follow-ups

- [ ] Isolate the combined power-button/fingerprint-sensor wake interaction. Keyboard
  and lid sleep work; do not disable devices or change firmware/kernel policy on
  the strength of the generic ACPI wake IRQ alone.
- [ ] Test full idle intervals while Caffeine and audio inhibitors are held,
  independently. Acquisition, native detection and release passed; extended action
  suppression and a real suspend-block challenge were not performed. Never bypass
  inhibitors to test them.
- [ ] User-test password recovery when the fingerprint reader is genuinely unavailable,
  retaining the prevalidated TTY/password recovery path. Normal password tests are
  not this failure-mode test; agents must not stop/claim/scan the reader.
- [ ] Test coverage of all connected outputs and reconnect/hotplug, including lock
  rendering across resume. Current observations do not certify every output or
  no-desktop-flash behavior.
- [ ] Review fallback retirement separately after remaining security checks. Keep
  swaylock/PAM/style installed; they cannot unlock a native compositor session lock.
- [ ] Resolve native wallpaper-pair policy before separately retiring the theme
  bridge/specialisations and remaining palette exports. No cleanup is authorized
  by this checkpoint alone.

### User-only validation

Save work and confirm the TTY/password recovery path before applying while unlocked.
First recheck manual lock/unlock. Then test idle lock, screen-off/activity recovery,
manual suspend/resume, lid behavior and output reconnect separately. An idle test can
sleep at 310 seconds; don't leave unsaved work. Caffeine/audio/Lid Guard can inhibit
parts of the trial as designed—only the user changes those states. Never force or
bypass their inhibitors just to test a path.

After activation, inspect logind's native Noctalia sleep-delay inhibitor and logs.
Configuration/mock tests cannot prove real lock-before-sleep or resume rendering.
No agent authentication, lock, display-power or sleep action is performed.

## Recovery boundary

The deployed native locker now depends on the dedicated PAM service/package patch;
it is no longer unused stage-one scaffolding. Do not remove them during recovery
while native locking is active. Installed swaylock is a rollback option, not a way
to unlock an existing native lock.

Niri's session-lock protocol can keep an abandoned lock secure: killing/restarting
a locked Noctalia is not a safe unlock procedure. Use the prevalidated TTY/password
recovery route to inspect the correct graphical session. Last-resort termination
or reboot can lose unsaved work and is the user's decision, never an agent action.

Roll back through a reviewed, consistent configuration while unlocked: restore both
the intended locker and its manual/idle/pre-sleep routes without racing two lockers.
Only the user activates that rollback. Keep fallback/auth files until that separate
review; do not revert the PAM foundation alone under the current native routes.
