#!/run/current-system/sw/bin/bash
# Monitor hotplug handler - re-applies wallpaper when monitors connect/disconnect
# This script is triggered by a systemd service that monitors for display changes

# Set up environment
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(@coreutils@/bin/id -u)/bus"

# Set WAYLAND_DISPLAY if not already set (needed for awww to find the correct socket)
if [ -z "$WAYLAND_DISPLAY" ]; then
  WAYLAND_DISPLAY=$(@coreutils@/bin/ls /run/user/$(@coreutils@/bin/id -u)/wayland-* 2>/dev/null | @gnugrep@/bin/grep -v 'lock\|awww' | @coreutils@/bin/head -n1 | @gnused@/bin/sed 's|.*/wayland-\([0-9]*\)|\1|')
  if [ -n "$WAYLAND_DISPLAY" ]; then
    export WAYLAND_DISPLAY="wayland-$WAYLAND_DISPLAY"
  fi
fi

# Wait a moment for the display subsystem to stabilize
sleep 1

# Check if awww daemon is running
if ! @awww@/bin/awww query &>/dev/null; then
  echo "awww daemon is not running, skipping wallpaper refresh"
  exit 0
fi

# Determine current theme mode
MODE=$(@darkman@/bin/darkman get 2>/dev/null) || MODE="dark"

# Select appropriate wallpaper based on current theme
if [ "$MODE" = "light" ]; then
  WALLPAPER="@wallpaper_light@"
else
  WALLPAPER="@wallpaper_dark@"
fi

# Re-apply wallpaper to all outputs with a smooth transition
@awww@/bin/awww img "$WALLPAPER" --transition-type simple --transition-duration 1

echo "Wallpaper refreshed for current outputs (mode: $MODE)"
