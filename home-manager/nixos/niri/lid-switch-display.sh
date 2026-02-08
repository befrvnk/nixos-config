#!/run/current-system/sw/bin/bash
# Lid switch handler - monitors ACPI events and controls internal display
# This script listens to acpid events via acpi_listen, bypassing systemd-logind
# NOTE: This works independently of systemd-logind's HandleLidSwitch, which is
# inhibited by Happy to prevent suspend during remote development sessions

# Set up environment for niri communication
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(@coreutils@/bin/id -u)/bus"

# Set WAYLAND_DISPLAY if not already set (needed for niri msg)
if [ -z "$WAYLAND_DISPLAY" ]; then
  WAYLAND_DISPLAY=$(@coreutils@/bin/ls /run/user/$(@coreutils@/bin/id -u)/wayland-* 2>/dev/null | @gnugrep@/bin/grep -v 'lock\|awww' | @coreutils@/bin/head -n1 | @gnused@/bin/sed 's|.*/wayland-\([0-9]*\)|\1|')
  if [ -n "$WAYLAND_DISPLAY" ]; then
    export WAYLAND_DISPLAY="wayland-$WAYLAND_DISPLAY"
  fi
fi

# Check initial lid state and set display accordingly
LID_STATE=$(@coreutils@/bin/cat /proc/acpi/button/lid/LID0/state 2>/dev/null | @gawk@/bin/awk '{print $2}')
if [ "$LID_STATE" = "closed" ]; then
  @niri@/bin/niri msg output eDP-1 off 2>/dev/null
  echo "Initial state: Lid closed - disabled eDP-1"
elif [ "$LID_STATE" = "open" ]; then
  @niri@/bin/niri msg output eDP-1 on 2>/dev/null
  echo "Initial state: Lid open - enabled eDP-1"
fi

# Listen for ACPI lid events and toggle display
@acpid@/bin/acpi_listen | while read -r line; do
  if echo "$line" | @gnugrep@/bin/grep -q "button/lid"; then
    # Small delay to let lid state file update
    @coreutils@/bin/sleep 0.2

    LID_STATE=$(@coreutils@/bin/cat /proc/acpi/button/lid/LID0/state 2>/dev/null | @gawk@/bin/awk '{print $2}')

    if [ "$LID_STATE" = "closed" ]; then
      @niri@/bin/niri msg output eDP-1 off 2>/dev/null
      echo "Lid closed - disabled eDP-1"
    elif [ "$LID_STATE" = "open" ]; then
      @niri@/bin/niri msg output eDP-1 on 2>/dev/null
      echo "Lid open - enabled eDP-1"
    fi
  fi
done
