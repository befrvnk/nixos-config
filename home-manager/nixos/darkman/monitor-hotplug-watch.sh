#!/run/current-system/sw/bin/bash
# Watch DRM udev events and refresh wallpaper after monitor changes.

@systemd@/bin/udevadm monitor --udev --subsystem-match=drm | while IFS= read -r line; do
  if printf '%s\n' "$line" | @gnugrep@/bin/grep -q "change"; then
    @coreutils@/bin/sleep 2
    "$HOME/.local/share/monitor-hotplug.sh"
  fi
done
