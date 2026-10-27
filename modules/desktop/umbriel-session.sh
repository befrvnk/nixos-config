# shellcheck shell=bash
set -e
# Standard HM profile expressions intentionally allow unset optional variables.

# The upstream native launcher doesn't enter Nushell's login profile. Load only the
# declarative HM session environment before its normal systemd import/start flow.
profile="@profiles@/$(@coreutils@/bin/id -un)"
if [ ! -r "$profile/etc/profile.d/hm-session-vars.sh" ]; then
  printf '%s\n' 'Umbriel trial: Home Manager session environment is unavailable' >&2
  exit 1
fi
# shellcheck disable=SC1091
. "$profile/etc/profile.d/hm-session-vars.sh"
export PATH="$profile/bin:${PATH:-/run/current-system/sw/bin}"
export XKB_CONFIG_ROOT=@xkb_root@
unset NIRI_SOCKET

# Logging out removes only the logind session; compositor/shell units survive in
# the persistent user manager (a Niri session kept Niri, Noctalia and the overview
# watcher running after logout). Clear that stale graphical session so this
# compositor's services start fresh instead of inheriting a dead Wayland socket.
@systemd@/bin/systemctl --user stop graphical-session.target || true

exec @umbriel@/bin/start-umbriel "$@"
