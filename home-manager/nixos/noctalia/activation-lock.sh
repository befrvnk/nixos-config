# Sourced into HM activation so fd 9 stays locked through linkGeneration.
if [ -z "${DRY_RUN_CMD:-}" ] && [ -z "${NOCTALIA_THEME_BRIDGE_ACTIVE:-}" ]; then
  # Never stop the parent if an old Darkman callback is still winding down.
  # A normal rebuild stops the legacy scheduler before linking the new files.
  if [ -z "${DARKMAN_RUNNING:-}" ] && @systemd@/bin/systemctl --user --quiet is-active darkman.service; then
    @systemd@/bin/systemctl --user stop darkman.service
  fi
  noctalia_runtime="${XDG_RUNTIME_DIR:-/run/user/$(@coreutils@/bin/id -u)}/noctalia-theme"
  @coreutils@/bin/mkdir -p "$noctalia_runtime"
  exec 9>"$noctalia_runtime/activation.lock"
  @util_linux@/bin/flock -w 120 9
fi
