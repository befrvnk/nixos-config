# 1Password SSH session

Goal: unlock 1Password once per login session, then use its SSH keys for Git
signing and `git push`/`pull` without further prompts. Suspending or shutting
down ends that session, so the keys stop being available.

## How it works

The signing and authentication keys live in 1Password and are non-exportable.
1Password's SSH agent asks you to approve a key once per application and keeps
that approval until 1Password locks or quits
([1Password SSH agent security](https://www.1password.dev/ssh/agent/security)).
While the app is locked the agent still runs, but the private keys are not in
memory, so the next request prompts for an unlock.

The current 60-minute idle auto-lock is therefore what forces an unlock for
most commits and pushes. Turning it off makes the app stay unlocked for the
whole session; a suspend hook restores the lock at the sleep boundary.

## Approval prompts

Unlocking and approving are separate. Auto-lock off leaves only the approval
prompt, controlled in **Settings → Developer → SSH agent → Advanced**:

- **Ask approval for each new**: keep the default **For each new application**.
  **For each new request** asks on every signature.
- **Remember key approval**: **Until 1Password locks** (default) wipes
  approvals at the suspend lock, so the first signing after resume asks once.
  **Until 1Password quits** keeps approvals across the suspend lock, since the
  app only quits at logout/shutdown; approve once per boot instead. A set
  duration (4/12/24 hours) is a middle ground. In every case the app still has
  to be unlocked before the key can be used.
- On the approval prompt, check **Approve for all applications** to let every
  process use that key until the approvals are wiped. Otherwise Git,
  `op-ssh-sign`, `ssh`, IDEs and GUI clients each ask once.

Commit signing therefore prompts at most once per key per session, not once
per commit. With **Until 1Password quits** and **Approve for all
applications**, that becomes once per key per boot. 1Password has no "never
ask" mode; removing the last prompt means moving signing to a key outside
1Password, which stores the private key on disk instead of keeping it
non-exportable.

## Manual 1Password settings

These settings are per device and not managed by Nix.

Linux (Framework):

1. **Settings → Security → Lock after the computer is idle**: turn off.
2. Leave **Lock when computer locks** off if only suspend/shutdown should end
   the session. Enabling it additionally locks 1Password every time the screen
   locks, which means another unlock after a manual lock.
3. Keep **Unlock using system authentication service** on so resuming only
   needs the fingerprint/PAM prompt.

macOS (MacBook):

1. **Settings → Security → Lock after the device is idle for**: turn off.
2. Turn on **Lock when device locks or sleeps**. macOS has this built in, so
   no extra service is needed there. It also locks when the display sleeps,
   not only on system suspend, so expect an unlock after the screen turns off.

A 1Password Business policy or MDM profile can enforce auto-lock and prevent
these changes; in that case the app cannot stay unlocked for a session.

## NixOS suspend hook

Linux 1Password has no "lock on sleep" option. `1password-lock-on-suspend`
(`home-manager/nixos/1password-session/`) listens for logind's
`PrepareForSleep` signal on the system bus and calls the app's
`com.onepassword.OnePassword.Lock` D-Bus method before suspend. The user
service is imported from `home-manager/nixos/frank.nix` and restarts if the
monitor process exits.

Shutdown and logout need no hook: quitting the app drops the keys.

## Verify

```bash
systemctl --user status 1password-lock-on-suspend
busctl --user introspect com.onepassword.OnePassword \
  /com/onepassword/onepassword | grep Lock

# Keys are listed only while 1Password is unlocked:
SSH_AUTH_SOCK=~/.1password/agent.sock ssh-add -l
```

Suspend and resume once, then repeat `ssh-add -l`: it should no longer list
keys, and the next signed commit or `git push` should ask for one unlock. The
hook's failures appear in `journalctl --user -u 1password-lock-on-suspend`.

To lock manually, for example to check the method without suspending:

```bash
busctl --user call com.onepassword.OnePassword \
  /com/onepassword/onepassword com.onepassword.OnePassword Lock
```

## Trade-offs

- While a session is unlocked, any process running as the user can use a key
  that has already been approved for that application. This is the same
  exposure as an OpenSSH agent holding a key; the private key itself still
  never leaves 1Password.
- With idle auto-lock off, the vault stays unlocked while the machine is
  awake, including when the screen is locked without suspending. Turn on
  **Lock when computer locks** if that matters more than staying unlocked
  through manual screen locks.
- If a 1Password update removes the D-Bus method, the hook logs an error and
  leaves the app unlocked. The fallback is to enable **Lock when computer
  locks** (Niri locks the screen before suspend here) or to set a long idle
  timeout instead of turning auto-lock off.
