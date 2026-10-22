#!/usr/bin/env bash
# Respect high-level sleep blockers without treating lid/idle inhibition as a
# global suspend veto. Never bypass logind's own policy or screen-lock delays.
set -euo pipefail

fail_closed() {
  printf '%s\n' "$1" >&2
  notify-send -t 5000 -i dialog-warning "Suspend Unavailable" "$1" || true
  exit 1
}

if (( $# > 1 )); then
  fail_closed "Usage: safe-suspend [--require-lock]"
fi
require_lock=false
case "${1:-}" in
  "") ;;
  --require-lock) require_lock=true ;;
  *) fail_closed "Usage: safe-suspend [--require-lock]" ;;
esac

if ! inhibitors=$(busctl --system --timeout=5s --json=short call \
  org.freedesktop.login1 /org/freedesktop/login1 \
  org.freedesktop.login1.Manager ListInhibitors); then
  fail_closed "Could not read sleep inhibitors; suspend was not requested."
fi

# ListInhibitors rows are [what, who, why, mode, uid, pid]. Validate the
# envelope/rows before filtering, so an unexpected response fails closed.
if ! blockers=$(jq -er '
  if .type != "a(ssssuu)" or (.data | type) != "array" or
     (.data | length) != 1 or (.data[0] | type) != "array" then
    error("invalid ListInhibitors response")
  else
    .data[0]
    | if all(.[];
        type == "array" and length == 6 and
        (.[0] | type) == "string" and (.[1] | type) == "string" and
        (.[2] | type) == "string" and (.[3] | type) == "string" and
        (.[4] | type) == "number" and (.[5] | type) == "number") then .
      else error("invalid ListInhibitors row") end
    | map(select(.[3] == "block" and ((.[0] | split(":") | index("sleep")) != null)))
    | map(.[1]) | unique | join(", ")
  end
' <<< "$inhibitors"); then
  fail_closed "Could not parse sleep inhibitors; suspend was not requested."
fi

if [[ -n "$blockers" ]]; then
  notify-send -t 5000 -i dialog-warning "Suspend Blocked" "$blockers is preventing sleep." || true
  exit 1
fi

# Native idle/power actions must not follow a failed/missing locker. Manual calls
# retain the normal PrepareForSleep path; native callers use the extra guard.
if $require_lock; then
  session="${XDG_SESSION_ID:-}"
  if [[ -z "$session" ]]; then
    if ! session=$(loginctl show-user "$UID" -p Display --value); then
      fail_closed "Could not resolve the graphical session; suspend was not requested."
    fi
  fi
  if [[ ! "$session" =~ ^[[:alnum:]][[:alnum:]_-]*$ ]]; then
    fail_closed "No valid graphical session; suspend was not requested."
  fi
  if ! locked=$(loginctl show-session "$session" -p LockedHint --value) || [[ "$locked" != yes ]]; then
    fail_closed "Session lock was not confirmed; suspend was not requested."
  fi
fi

# Delay and block-weak locks are left to logind, as are authorization and races
# with blockers acquired after our snapshot. No ignore-inhibitors option is used.
exec systemctl suspend
