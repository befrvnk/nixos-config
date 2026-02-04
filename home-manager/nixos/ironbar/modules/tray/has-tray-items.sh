#!/usr/bin/env bash
# Check if there are any non-passive StatusNotifierItems (tray icons)
# Exit 0 if active items exist (show tray), exit 1 if all passive or empty (hide tray)

# Get registered items
items=$(dbus-send --session --print-reply --dest=org.kde.StatusNotifierWatcher \
  /StatusNotifierWatcher org.freedesktop.DBus.Properties.Get \
  string:org.kde.StatusNotifierWatcher string:RegisteredStatusNotifierItems 2>/dev/null)

# Extract item addresses (format: ":1.123/org/path/to/item")
addresses=$(echo "$items" | grep -oP 'string "\K[^"]+')

if [[ -z "$addresses" ]]; then
  exit 1  # No items at all
fi

# Check each item's Status property
while IFS= read -r addr; do
  # Split into bus name and object path
  bus_name="${addr%%/*}"
  object_path="/${addr#*/}"

  # Query the Status property
  status=$(dbus-send --session --print-reply --dest="$bus_name" "$object_path" \
    org.freedesktop.DBus.Properties.Get \
    string:org.kde.StatusNotifierItem string:Status 2>/dev/null | grep -oP 'string "\K[^"]+')

  # If any item is not Passive, show the tray
  if [[ "$status" != "Passive" ]]; then
    exit 0
  fi
done <<< "$addresses"

# All items are Passive (or couldn't be queried)
exit 1
