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
USER_ID="$(@coreutils@/bin/id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$USER_ID}"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"
export DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNTIME_DIR/bus"

# Serialise darkman-triggered Home Manager specialisation activations. Concurrent
# linkGeneration runs can kill each other's find/xargs children and make a
# rebuild fail even though a retry succeeds.
LOCK_FILE="$RUNTIME_DIR/darkman-home-manager-activation.lock"
exec 9>"$LOCK_FILE"
if ! @util_linux@/bin/flock -w 120 9; then
  echo "Error: Timed out waiting for darkman Home Manager activation lock" >&2
  exit 1
fi

# If a normal home-manager-frank.service activation is already running, let it
# finish before applying a dark/light specialisation. When this script is called
# from the Home Manager activation hook itself, DARKMAN_FROM_HOME_MANAGER skips
# the wait to avoid deadlocking against the parent oneshot service.
if [ -z "${DARKMAN_FROM_HOME_MANAGER:-}" ]; then
  for _attempt in {1..120}; do
    HM_STATE=$(@systemd@/bin/systemctl show -P ActiveState home-manager-frank.service 2>/dev/null || true)
    HM_JOBS=$(@systemd@/bin/systemctl list-jobs --no-legend --plain 2>/dev/null | @gnugrep@/bin/grep -c 'home-manager-frank\.service' || true)

    if [ "$HM_STATE" != "activating" ] && [ "$HM_STATE" != "deactivating" ] && [ "$HM_STATE" != "reloading" ] && [ "${HM_JOBS:-0}" = "0" ]; then
      break
    fi

    @coreutils@/bin/sleep 0.5
  done
fi

# Set WAYLAND_DISPLAY if not already set (needed for awww to find the correct socket)
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
  # Try to find the Wayland display from socket files
  # Retry up to 5 times with 0.5s delay to handle boot race conditions
  for _attempt in {1..5}; do
    WAYLAND_NUM=$(@coreutils@/bin/ls "$RUNTIME_DIR"/wayland-* 2>/dev/null | @gnugrep@/bin/grep -v 'lock\|awww' | @coreutils@/bin/head -n1 | @gnused@/bin/sed 's|.*/wayland-\([0-9]*\)|\1|')
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
HM_GEN=$(
  /run/current-system/sw/bin/nix-store -qR /run/current-system \
    | /run/current-system/sw/bin/grep home-manager-generation \
    | while IFS= read -r gen; do
        if [ -d "$gen/specialisation" ]; then
          echo "$gen"
          break
        fi
      done
)

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

# Restart vicinae to pick up the regenerated stylix.toml theme
# The settings.json already points to "stylix" for both modes - colors come from stylix.toml
@systemd@/bin/systemctl --user restart vicinae.service || true


# Trigger Niri screen transition effect
NIRI_SOCKET=$(/run/current-system/sw/bin/find "$RUNTIME_DIR" -maxdepth 1 -name 'niri*.sock' 2>/dev/null | /run/current-system/sw/bin/head -n1)
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

# Update Nushell theme (running sessions will pick this up via pre_prompt hook)
NUSHELL_STATE_DIR="$HOME/.local/state/nushell"
@coreutils@/bin/mkdir -p "$NUSHELL_STATE_DIR"
@coreutils@/bin/cp "$HOME/.config/nushell/theme-$MODE.nuon" "$NUSHELL_STATE_DIR/theme.nuon"
