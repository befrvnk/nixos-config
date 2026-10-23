# Sourced into HM activation so fd 9 stays locked through linkGeneration.
if [ -z "${DRY_RUN_CMD:-}" ] && [ -z "${NOCTALIA_THEME_BRIDGE_ACTIVE:-}" ]; then
  # Boot-time system activation can precede the user manager and runtime dir.
  noctalia_runtime_root="${XDG_RUNTIME_DIR:-/run/user/$(@coreutils@/bin/id -u)}"
  if [ -d "$noctalia_runtime_root" ] && [ -O "$noctalia_runtime_root" ]; then
    export XDG_RUNTIME_DIR="$noctalia_runtime_root"
    # Stop the legacy scheduler before taking locks it may already hold.
    # Never stop the parent if an old Darkman callback is winding down.
    if [ -z "${DARKMAN_RUNNING:-}" ] && [ -S "$noctalia_runtime_root/bus" ] &&
      @systemd@/bin/systemctl --user --quiet is-active darkman.service; then
      @systemd@/bin/systemctl --user stop darkman.service
    fi
  fi

  # Keep this path identical to the bridge worker's explicit lock path.
  noctalia_lock=@activation_lock@
  (umask 077; @coreutils@/bin/mkdir -p "${noctalia_lock%/*}")
  exec 9>"$noctalia_lock"
  @util_linux@/bin/flock -w 120 9

  if [ -d "$noctalia_runtime_root" ] && [ -O "$noctalia_runtime_root" ]; then
    # Also serialize with the older runtime-lock worker during this upgrade.
    (umask 077; @coreutils@/bin/mkdir -p "$noctalia_runtime_root/noctalia-theme")
    exec {noctalia_legacy_fd}>"$noctalia_runtime_root/noctalia-theme/activation.lock"
    @util_linux@/bin/flock -w 120 "$noctalia_legacy_fd"
  fi
fi
