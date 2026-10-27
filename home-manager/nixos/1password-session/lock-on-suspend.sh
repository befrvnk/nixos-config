#!/usr/bin/env bash
# Lock 1Password when the system suspends so its SSH agent stops serving keys.
#
# Idle auto-lock is disabled (see docs/1password-ssh-session.md), so without
# this hook 1Password would stay unlocked across sleep and the SSH keys would
# remain available after resume. Linux has no built-in "lock on sleep"; the
# app exposes a Lock method on the session bus, which this waits to call.

set -o pipefail

# gdbus block-buffers stdout when piped; line-buffer it so the lock happens
# before logind freezes user processes.
stdbuf -oL gdbus monitor --system \
  --dest org.freedesktop.login1 \
  --object-path /org/freedesktop/login1 |
while read -r line; do
  case "$line" in
    *PrepareForSleep*"(true"*)
      if ! busctl --user --timeout=5 call com.onepassword.OnePassword \
        /com/onepassword/onepassword com.onepassword.OnePassword Lock; then
        echo "1password-lock-on-suspend: could not lock 1Password" >&2
      fi
      ;;
  esac
done
