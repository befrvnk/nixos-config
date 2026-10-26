# shellcheck shell=bash
set -e
# Standard HM profile expressions intentionally allow unset optional variables.

# The pinned native launcher doesn't enter Nushell's login profile. Load only the
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
exec @umbriel@/bin/start-umbriel "$@"
