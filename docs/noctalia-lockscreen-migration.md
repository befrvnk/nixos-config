# Native Noctalia lock-screen migration

This is a security-sensitive, staged migration from swaylock. Native Noctalia is
pinned at V5.3.0. The agent must not lock/suspend, enter/test passwords, use the
fingerprint reader, restart a locked session, or activate the system configuration.

## Stage 1: password authentication preflight (accepted)

During stage 1, **swaylock and all existing routes remained active and native
locking stayed disabled**. Stage 2 below is now activated, with password/fingerprint
unlock confirmed by the user; automatic-route cutover is still a later stage.

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

## Stage 3: automatic-route cutover (not implemented)

After native manual password/fingerprint/rendering acceptance, enable native
lock-before-sleep delay handling, switch idle lock and coordinated DPMS to native
commands, and remove obsolete swayidle lock/sleep listeners without racing lockers.
Keep idle timings, audio inhibition and safe-suspend policy. User tests idle,
screen-off/resume, output reconnect and suspend/lid scenarios separately. Only then
retire the old default lock style/path and remaining theme compatibility consumers.

## Recovery boundary

Stage 1 doesn't replace the running locker or change any existing PAM service.
Revert the stage-1 commit/configuration and rebuild to remove the unused service/
package patch. A future native-lock recovery plan must account for Niri's session-lock
protocol: killing/restarting a locked client is not a safe unlock procedure and
ending the graphical session can lose unsaved work. Keep that decision with the user.
