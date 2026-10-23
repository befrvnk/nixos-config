# Defer pre-session requests; the native shell's startup hook will retry them.
if [ -z "${DRY_RUN_CMD:-}" ] && [ -z "${NOCTALIA_THEME_BRIDGE_ACTIVE:-}" ]; then
  @theme_request@ --force --refresh
  if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -S "$XDG_RUNTIME_DIR/bus" ]; then
    @systemd@/bin/systemctl --user --no-block start noctalia-theme.path
  fi
fi
