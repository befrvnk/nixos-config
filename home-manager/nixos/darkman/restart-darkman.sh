#!/run/current-system/sw/bin/bash
# Restart darkman after Home Manager activation unless darkman is already running.

if [ -n "${DARKMAN_RUNNING:-}" ]; then
  exit 0
fi

$DRY_RUN_CMD @systemd@/bin/systemctl --user restart darkman.service || true

if [ -n "$DRY_RUN_CMD" ]; then
  exit 0
fi

for _attempt in {1..10}; do
  if @awww@/bin/awww query &>/dev/null; then
    MODE=$(@darkman@/bin/darkman get 2>/dev/null) || MODE="dark"
    "$HOME/.local/share/darkman-switch-mode.sh" "$MODE" &>/dev/null || true
    exit 0
  fi

  @coreutils@/bin/sleep 0.5
done
