# shellcheck shell=bash
action="${1:-}"
runtime_dir="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/brightness-ctl"
mkdir -p "$runtime_dir"
target_file="$runtime_dir/target"
lock_file="$runtime_dir/ddc.lock"

# Internal display: use brightnessctl (synchronous, no race condition)
case "$action" in
  raise) brightnessctl -q set 5%+ || exit $? ;;
  lower) brightnessctl -q set 5%- || exit $? ;;
  *) echo "Usage: brightness-ctl <raise|lower>"; exit 1 ;;
esac

# Read current brightness percentage
target=$(brightnessctl -m | awk -F, '{gsub(/%/,""); print $4}')

# Display only; hardware changes remain with brightnessctl/DDC. A missing shell
# must not prevent the external monitor from receiving its brightness update.
noctalia msg brightness-osd "${target}%" || true

# Write target for external monitor
echo "$target" > "$target_file"

# Sync external monitor in background
(
  # If another sync is running, it will pick up the new target when done
  if [[ -f "$lock_file" ]]; then
    exit 0
  fi

  touch "$lock_file"
  trap 'rm -f "$lock_file"' EXIT

  # Keep syncing until target stops changing
  while true; do
    current_target=$(cat "$target_file" 2>/dev/null || echo "")
    [[ -z "$current_target" ]] && break

    # Set external monitor to target brightness
    ddcutil setvcp 10 "$current_target" 2>/dev/null

    # Check if target changed while we were running
    new_target=$(cat "$target_file" 2>/dev/null || echo "")
    if [[ "$new_target" == "$current_target" ]]; then
      break  # Target unchanged, we're done
    fi
    # Target changed, loop to sync again
  done
) &
