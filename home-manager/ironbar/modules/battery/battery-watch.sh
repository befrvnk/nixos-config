#!/usr/bin/env bash
# Battery status watcher - outputs on upower events
# Dependencies injected via pkgs.writeShellScript in default.nix

get_battery_status() {
  BATTERY_DEVICE=""
  BATTERY=""

  for device in $(upower -e | grep battery); do
    INFO=$(upower -i "$device")
    if echo "$INFO" | grep -q "should be ignored"; then
      continue
    fi
    if echo "$INFO" | grep -q "power supply.*no"; then
      continue
    fi
    BATTERY_DEVICE="$device"
    BATTERY="$INFO"
    break
  done

  if [[ -z "$BATTERY" ]]; then
    echo "󱉝 N/A"
    return
  fi

  PERCENT=$(echo "$BATTERY" | grep "percentage" | awk '{print $2}' | tr -d '%')
  STATE=$(echo "$BATTERY" | grep -E "^\s+state:" | awk '{print $2}')

  # Icon selection based on state and percentage
  if [[ "$STATE" == "charging" ]]; then
    if   [[ $PERCENT -ge 90 ]]; then ICON="󰂅"
    elif [[ $PERCENT -ge 80 ]]; then ICON="󰂋"
    elif [[ $PERCENT -ge 70 ]]; then ICON="󰂊"
    elif [[ $PERCENT -ge 60 ]]; then ICON="󰢞"
    elif [[ $PERCENT -ge 50 ]]; then ICON="󰂉"
    elif [[ $PERCENT -ge 40 ]]; then ICON="󰢝"
    elif [[ $PERCENT -ge 30 ]]; then ICON="󰂈"
    elif [[ $PERCENT -ge 20 ]]; then ICON="󰂇"
    elif [[ $PERCENT -ge 10 ]]; then ICON="󰂆"
    else ICON="󰢜"
    fi
  elif [[ "$STATE" == "fully-charged" ]]; then
    ICON="󰁹"
  else
    if   [[ $PERCENT -ge 90 ]]; then ICON="󰂂"
    elif [[ $PERCENT -ge 80 ]]; then ICON="󰂁"
    elif [[ $PERCENT -ge 70 ]]; then ICON="󰂀"
    elif [[ $PERCENT -ge 60 ]]; then ICON="󰁿"
    elif [[ $PERCENT -ge 50 ]]; then ICON="󰁾"
    elif [[ $PERCENT -ge 40 ]]; then ICON="󰁽"
    elif [[ $PERCENT -ge 30 ]]; then ICON="󰁼"
    elif [[ $PERCENT -ge 20 ]]; then ICON="󰁻"
    elif [[ $PERCENT -ge 10 ]]; then ICON="󰁺"
    else ICON="󰂎"
    fi
  fi

  echo "$ICON $PERCENT%"
}

# Emit initial status
get_battery_status

# Watch for battery events and emit on changes
upower --monitor-detail 2>/dev/null | while read -r line; do
  case "$line" in
    *percentage*|*state*|*time-to-*|*energy*)
      get_battery_status
      ;;
  esac
done
