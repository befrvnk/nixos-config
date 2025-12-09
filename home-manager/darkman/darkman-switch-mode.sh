#!/run/current-system/sw/bin/bash
# Darkman theme switching script
# Usage: darkman-switch-mode.sh <light|dark>

MODE="$1"

if [ "$MODE" != "light" ] && [ "$MODE" != "dark" ]; then
  echo "Error: Invalid mode. Use 'light' or 'dark'" >&2
  exit 1
fi

# Set environment variable to prevent infinite restart loop
export DARKMAN_RUNNING=1
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(@coreutils@/bin/id -u)/bus"

# Set WAYLAND_DISPLAY if not already set (needed for awww to find the correct socket)
if [ -z "$WAYLAND_DISPLAY" ]; then
  # Try to find the Wayland display from socket files
  # Retry up to 5 times with 0.5s delay to handle boot race conditions
  for attempt in {1..5}; do
    WAYLAND_NUM=$(@coreutils@/bin/ls /run/user/$(@coreutils@/bin/id -u)/wayland-* 2>/dev/null | @gnugrep@/bin/grep -v 'lock\|awww' | @coreutils@/bin/head -n1 | @gnused@/bin/sed 's|.*/wayland-\([0-9]*\)|\1|')
    if [ -n "$WAYLAND_NUM" ]; then
      export WAYLAND_DISPLAY="wayland-$WAYLAND_NUM"
      break
    fi
    @coreutils@/bin/sleep 0.5
  done
fi

# Warn if WAYLAND_DISPLAY couldn't be detected (wallpaper update will fail)
if [ -z "$WAYLAND_DISPLAY" ]; then
  echo "Warning: Could not detect WAYLAND_DISPLAY, wallpaper may not update" >&2
fi

# Find the home-manager generation with specialisations from the current system
HM_GEN=$(/run/current-system/sw/bin/nix-store -qR /run/current-system | /run/current-system/sw/bin/grep home-manager-generation | while read gen; do
  if [ -d "$gen/specialisation" ]; then
    echo "$gen"
    break
  fi
done)

if [ -z "$HM_GEN" ]; then
  echo "Error: Could not find home-manager generation with specialisations" >&2
  exit 1
fi

"$HM_GEN/specialisation/$MODE/activate"

# Set freedesktop portal color scheme preference AFTER specialization activation
# This ensures Stylix doesn't override it
@dconf@/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-$MODE'"

# Restart Ironbar to pick up new theme CSS
@systemd@/bin/systemctl --user restart ironbar.service || true

# Restart SwayOSD to pick up new GTK theme colors
@systemd@/bin/systemctl --user restart swayosd.service || true

# Update vicinae theme based on mode
if [ -f ~/.config/vicinae/vicinae.json ]; then
  if [ "$MODE" = "light" ]; then
    VICINAE_THEME="catppuccin-latte"
  else
    VICINAE_THEME="catppuccin-mocha"
  fi

  @jq@/bin/jq ".theme.name = \"$VICINAE_THEME\"" ~/.config/vicinae/vicinae.json > ~/.config/vicinae/vicinae.json.tmp && \
  mv ~/.config/vicinae/vicinae.json.tmp ~/.config/vicinae/vicinae.json
  @systemd@/bin/systemctl --user restart vicinae.service || true
fi

# Trigger Niri screen transition effect
NIRI_SOCKET=$(/run/current-system/sw/bin/find /run/user/* -maxdepth 1 -name 'niri*.sock' 2>/dev/null | /run/current-system/sw/bin/head -n1)
if [ -n "$NIRI_SOCKET" ]; then
  NIRI_SOCKET="$NIRI_SOCKET" @niri@/bin/niri msg action do-screen-transition
fi

# Switch wallpaper using awww with fade transition
if [ "$MODE" = "light" ]; then
  WALLPAPER="@wallpaper_light@"
else
  WALLPAPER="@wallpaper_dark@"
fi

# Change wallpaper with fade transition (no daemon restart needed)
@awww@/bin/awww img "$WALLPAPER" --transition-type simple --transition-duration 1
