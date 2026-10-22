# Native Noctalia lock-screen migration

This is a security-sensitive, staged migration from swaylock. Native Noctalia is
pinned at V5.3.0. The agent must not lock/suspend, enter/test passwords, use the
fingerprint reader, restart a locked session, or activate the system configuration.

## Stage 1: password authentication preflight (accepted)

**Swaylock and all existing lock/idle/suspend routes remain active. Noctalia's native
lock screen remains disabled.** There is no automatic native-lock cutover here.

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

## Stage 2: native screen and route cutover (not implemented)

Only after preflight passes:

1. Review native fingerprint user identity/claim/release, account-policy differences,
   lid-reader disable behavior, password fallback and suspend-delay handling.
2. Enable secure defaults: no passwordless grace, no empty-password submission, no
   desktop capture; start with lock transitions disabled to simplify suspend timing.
3. Retain a documented swaylock rollback and an independently working TTY/password
   recovery route. Save work before manual lock tests. Do not assume stopping the
   native client unlocks the compositor: abandoned session locks may remain secure.
4. Switch manual and idle routes, avoiding two competing lockers/logind listeners.
   Keep idle timings, audio inhibition and safe-suspend policy. Let native Noctalia
   own lock-before-sleep delay; coordinate monitor power through its own IPC.
5. User manually tests password, rejection, fingerprint, unavailable-reader fallback,
   multiple outputs, idle lock, screen-off/resume and suspend/lid scenarios one at
   a time. The agent never performs those hardware/session actions.
6. Remove the old default lock path only after acceptance; don't retire the remaining
   theme bridge just because a new native screen can render.

## Recovery boundary

Stage 1 doesn't replace the running locker or change any existing PAM service.
Revert the stage-1 commit/configuration and rebuild to remove the unused service/
package patch. A future native-lock recovery plan must account for Niri's session-lock
protocol: killing/restarting a locked client is not a safe unlock procedure and
ending the graphical session can lose unsaved work. Keep that decision with the user.
