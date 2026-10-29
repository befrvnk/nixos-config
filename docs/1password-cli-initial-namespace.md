# 1Password CLI ↔ desktop app: initial user namespace requirement

Status: root-caused and fixed on the Framework host (2026-10-29). The CLI
desktop-app integration works only while the 1Password app runs in the initial
user namespace.

## Symptom

Every `op` invocation fails with:

```
[ERROR] ... connecting to desktop app: read: connection reset, ...
```

The app log (`~/.config/1Password/logs/1Password_rNNNNN.log`) records the
rejection for each attempt:

```
WARN ... [1P:foundation/op-sys-info/src/process_information/linux.rs:409]
        invalid group attempted to connect, rejecting remote
ERROR ... Failed to accept new connection.: PipeAuthError(NoCreds)
```

## Root cause

1Password's Linux CLI integration authenticates peers on the
`/run/user/1000/1Password-BrowserSupport.sock` listener by comparing the
connecting process's **effective GID** to the `onepassword-cli` group (see the
[app integration security model](https://www.1password.dev/cli/app-integration-security.md)).
NixOS ships `op` through a set-gid wrapper (`programs._1password`), so a CLI
process starts with egid 31002.

The breakage: the running 1Password app instance was not in the initial user
namespace. A session-launched instance had

- `uid_map = 1000 1000 1`, `gid_map = 100 100 1` (only uid 1000 / gid 100 mapped)
- `NoNewPrivileges=1`

Inside that namespace gid 31002 is **unmapped**: `SO_PEERCRED` reports the peer's
credentials translated into the reader's namespace, so an *always-correct* peer
reads as an invalid ID. No fix on the CLI side can satisfy the check — verified
with the nixpkgs wrapper, a byte-identical upstream copy at `/usr/local/bin/op`
(`2755 root:onepassword-cli`), CLI 2.30.3 and 2.41.1, and a synthetic C probe
holding egid 31002 for its whole lifetime: every variant was rejected. The proof
of the diagnosis was relaunching the app from a terminal in the initial
namespace, after which `op account list` succeeded immediately.

Unmapped-by-namespace is indistinguishable from a missing group when reading
`/proc/<pid>/status` from a different namespace, which is why the wrapper's
group looked wrong at first: every non-mapped gid displays the same as
`nogroup` there.

## Fix

`home-manager/nixos/1password-app.nix` starts the app as a
`graphical-session.target` user service (`1password-app`). User services exec in
the user manager's initial namespace, where the kernel-applied setgid GID of the
CLI wrapper is visible to the app. `Restart=on-failure` so quitting from the
tray stays quit.

Notes:

- The app is single-instance; manual launches exit when the service instance is
  running.
- 1Password has no `~/.config/autostart` entry, so no autostart shadowing is
  needed. If the app is ever relaunched through an issue path again, the symptom
  returns for that instance; `systemctl --user status 1password-app` verifies
  which instance owns the tray.
- Quick check of the namespace state:
  `cat /proc/$(pgrep -f share/1password/1password | head -1)/uid_map`
  — `0 0 4294967295` is healthy; `1000 1000 1` is the broken state.

## Investigation record

- Wrapper attributes are correct: `/run/wrappers/bin/op` is
  `-r-x--s--x root onepassword-cli`; the Nix store binary is byte-identical to
  the upstream download (nixpkgs' autoPatchelf leaves it unchanged).
- An effective-gid *drop* happens inside op itself on every platform
  (kernel grants egid 31002 at exec, op drops it to its real gid while keeping
  the saved-set GID for re-raising at connect). Reproduced identically for CLI
  2.41.0/2.41.1 and 2.30.3 from the wrapper and from `/usr/local/bin/op`, so it
  is not the regression: the app-side namespace was.
- The store binary is not stripped/patched by nixpkgs in ways that change
  behavior (`cmp` against the official zip: identical).
- `programs._1password-gui`'s `polkitPolicyOwners` and "Integrate with 1Password
  CLI" (`developers.cliSharedLockState.enabled`) were already enabled and are
  unrelated to this failure mode.
