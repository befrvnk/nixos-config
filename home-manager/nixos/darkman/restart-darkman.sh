#!/run/current-system/sw/bin/bash
# Re-apply the current darkman mode after Home Manager activation.
#
# Do not restart darkman here. Starting/restarting darkman immediately runs its
# mode hook, which itself activates a Home Manager Stylix specialisation. During
# a NixOS switch that can overlap with home-manager-frank.service and race in
# linkGeneration. The systemd unit is kept running across rebuilds instead.

if [ -n "${DARKMAN_RUNNING:-}" ]; then
  exit 0
fi

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
