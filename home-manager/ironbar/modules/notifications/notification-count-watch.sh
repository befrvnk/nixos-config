#!/usr/bin/env bash
# Notification count watcher - outputs on D-Bus notification events

get_notification_count() {
  COUNTS=$(dunstctl count)
  HISTORY=$(echo "$COUNTS" | grep "History:" | awk '{print $2}')

  if [[ $HISTORY -eq 0 ]]; then
    echo "󰂜 0"
  else
    echo "󰂚 $HISTORY"
  fi
}

# Emit initial count
get_notification_count

# Watch for notification D-Bus signals from both standard interface and dunst-specific
# - org.freedesktop.Notifications: standard notification events
# - org.dunstproject.cmd0: dunst-specific events (history clear, close all, etc.)
# - sender=org.freedesktop.Notifications: catches all signals from dunst daemon
dbus-monitor --profile "sender='org.freedesktop.Notifications'" 2>/dev/null | while read -r line; do
  # Trigger on notification-related signals
  case "$line" in
    *Notify*|*CloseNotification*|*NotificationClosed*|*ActionInvoked*|*NotificationHistoryCleared*|*PropertiesChanged*)
      sleep 0.1  # Debounce rapid events
      get_notification_count
      ;;
  esac
done
