#!/usr/bin/env bash
# Battery notification monitor (event-driven shell script)
#
# Uses 'upower --monitor-detail' to watch battery changes via a persistent D-Bus connection.
# This is event-driven and creates only ONE D-Bus connection for the lifetime of the script.
#
# Sends notifications for:
# - 5% battery (critical) when discharging
# - 20% battery (low) when discharging
# - 100% battery (full) when charging

set -euo pipefail

# State directory for tracking sent notifications
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
STATE_DIR="$RUNTIME_DIR/battery-notify"
mkdir -p "$STATE_DIR"

SENT_5="$STATE_DIR/sent_5"
SENT_20="$STATE_DIR/sent_20"
SENT_FULL="$STATE_DIR/sent_full"

# Find the battery device path
find_battery() {
    local devices
    devices=$(upower -e | grep -i battery || true)

    for device in $devices; do
        local info
        info=$(upower -i "$device")

        # Skip if should be ignored or not a power supply
        if echo "$info" | grep -q "should be ignored.*yes"; then
            continue
        fi
        if echo "$info" | grep -q "power supply.*no"; then
            continue
        fi

        # Found valid battery
        echo "$device"
        return 0
    done

    return 1
}

# Validate percentage is a number between 0-100
validate_percentage() {
    local value="$1"
    if [[ -z "$value" ]] || ! [[ "$value" =~ ^[0-9]+$ ]]; then
        return 1
    fi
    if [[ $value -lt 0 ]] || [[ $value -gt 100 ]]; then
        return 1
    fi
    return 0
}

# Send a desktop notification
send_notification() {
    local urgency="$1"
    local summary="$2"
    local body="$3"
    local icon="$4"

    notify-send -u "$urgency" -i "$icon" "$summary" "$body"
    echo "Sent notification: $summary" >&2
}

# Check battery state and send notifications if needed
check_battery_state() {
    local percentage="$1"
    local state="$2"

    # Skip if percentage is invalid (prevents false alerts from empty/malformed values)
    if ! validate_percentage "$percentage"; then
        echo "Warning: Invalid percentage '$percentage', skipping check" >&2
        return
    fi

    # Handle discharging state
    if [[ "$state" == "discharging" ]]; then
        # Reset full charge notification only when battery drops meaningfully
        # This prevents notification spam from load-induced fluctuations near 100%
        if [[ $percentage -lt 95 ]]; then
            rm -f "$SENT_FULL"
        fi

        # Check for 5% battery (critical)
        if [[ $percentage -le 5 ]] && [[ ! -f "$SENT_5" ]]; then
            send_notification \
                "critical" \
                "Battery Critical!" \
                "Battery at ${percentage}%. Please plug in your charger immediately." \
                "battery-caution"
            touch "$SENT_5"
            # Also reset the 20% notification for next charge cycle
            rm -f "$SENT_20"

        # Check for 20% battery (low)
        elif [[ $percentage -le 20 ]] && [[ ! -f "$SENT_20" ]]; then
            send_notification \
                "normal" \
                "Battery Low" \
                "Battery at ${percentage}%. Consider plugging in your charger." \
                "battery-low"
            touch "$SENT_20"

        # Reset notifications when battery goes above thresholds
        elif [[ $percentage -gt 20 ]] && [[ -f "$SENT_20" ]]; then
            rm -f "$SENT_20" "$SENT_5"
        fi

    # Handle charging/fully-charged states
    elif [[ "$state" == "charging" ]] || [[ "$state" == "fully-charged" ]]; then
        # Reset low battery notifications when charging
        rm -f "$SENT_5" "$SENT_20"

        # Check if battery is full
        if [[ "$state" == "fully-charged" ]] && [[ ! -f "$SENT_FULL" ]]; then
            send_notification \
                "normal" \
                "Battery Fully Charged" \
                "Your battery is at 100%. You can unplug the charger." \
                "battery-full-charged"
            touch "$SENT_FULL"
        fi
    fi
}

# Main monitoring loop
main() {
    echo "Battery notification monitor starting..." >&2

    # Find battery device
    local battery_device
    if ! battery_device=$(find_battery); then
        echo "Error: No battery found" >&2
        exit 1
    fi

    echo "Monitoring battery: $battery_device" >&2

    # Extract the native-path (e.g., "BAT1") from the battery device for secondary validation
    local battery_native_path
    battery_native_path=$(upower -i "$battery_device" | grep "native-path:" | awk '{print $2}')
    echo "Battery native-path: $battery_native_path" >&2

    # Get initial battery state
    local info
    info=$(upower -i "$battery_device")
    local percentage
    percentage=$(echo "$info" | grep "percentage:" | awk '{print $2}' | tr -d '%')
    local state
    state=$(echo "$info" | grep "state:" | awk '{print $2}')

    # Check initial state
    check_battery_state "$percentage" "$state"

    echo "Battery notification monitor started (event-driven mode)" >&2

    # Monitor battery changes using upower --monitor-detail
    # This maintains a single persistent D-Bus connection and streams changes
    # Track last checked state in a file to avoid duplicate notifications on periodic updates
    local last_state_file="$STATE_DIR/last_state"
    local monitoring_device=false

    # Event-local variables (reset for each device changed event)
    local event_percentage=""
    local event_state=""
    local event_native_path=""

    while read -r line; do
        # Track which device we're currently reading data for
        if [[ "$line" =~ device\ changed:[[:space:]]+(.+) ]]; then
            local current_device="${BASH_REMATCH[1]}"
            # Only monitor our specific battery device, ignore other batteries (mouse, keyboard, etc)
            if [[ "$current_device" == "$battery_device" ]]; then
                monitoring_device=true
                # Reset event-local variables for fresh parsing of this event
                event_percentage=""
                event_state=""
                event_native_path=""
            else
                monitoring_device=false
            fi
            continue
        fi

        # Only parse data if we're monitoring our specific battery device
        if [[ "$monitoring_device" == false ]]; then
            continue
        fi

        # Parse native-path for secondary validation (guards against race conditions on resume)
        # This ensures we only process data from the actual laptop battery, not mouse/keyboard
        if [[ "$line" =~ native-path:[[:space:]]+([^[:space:]]+) ]]; then
            event_native_path="${BASH_REMATCH[1]}"
            # If native-path doesn't match our battery, stop monitoring this event
            if [[ "$event_native_path" != "$battery_native_path" ]]; then
                monitoring_device=false
            fi
            continue
        fi

        # Parse state changes (comes before percentage in upower output)
        if [[ "$line" =~ state:[[:space:]]+([a-z-]+) ]]; then
            event_state="${BASH_REMATCH[1]}"
        fi

        # Parse percentage changes (comes after state in upower output)
        # Trigger check here since this is the last field we need
        if [[ "$line" =~ percentage:[[:space:]]+([0-9]+)% ]]; then
            event_percentage="${BASH_REMATCH[1]}"

            # Check battery state only when we have BOTH values from THIS event
            # and native-path was validated (guards against processing wrong device)
            if [[ -n "$event_percentage" ]] && [[ -n "$event_state" ]] && [[ "$event_native_path" == "$battery_native_path" ]]; then
                local current_state="${event_percentage}_${event_state}"
                local last_state=""
                [[ -f "$last_state_file" ]] && last_state=$(cat "$last_state_file")

                if [[ "$current_state" != "$last_state" ]]; then
                    check_battery_state "$event_percentage" "$event_state"
                    echo "$current_state" > "$last_state_file"
                fi
            fi
        fi
    done < <(upower --monitor-detail)
}

main "$@"
