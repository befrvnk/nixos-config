#!/usr/bin/env bash
# Check if there are any StatusNotifierItems (tray icons) registered
# Exit 0 if items exist (show tray), exit 1 if empty (hide tray)

items=$(dbus-send --session --print-reply --dest=org.kde.StatusNotifierWatcher \
  /StatusNotifierWatcher org.freedesktop.DBus.Properties.Get \
  string:org.kde.StatusNotifierWatcher string:RegisteredStatusNotifierItems 2>/dev/null)

# Check if the array contains any items (look for "string" entries in the output)
if echo "$items" | grep -q 'string "'; then
  exit 0  # Has items, show tray
else
  exit 1  # No items, hide tray
fi
