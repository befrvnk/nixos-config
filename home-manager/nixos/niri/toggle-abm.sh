ABM_PATH="/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings"
if [[ -f "$ABM_PATH" ]]; then
  CURRENT=$(cat "$ABM_PATH" 2>/dev/null || echo "0")
  if [[ "$CURRENT" -eq 0 ]]; then
    echo 3 | tee "$ABM_PATH" > /dev/null 2>&1 || true
    notify-send -t 3000 -i display-brightness "ABM" "Enabled (power saving)"
  else
    echo 0 | tee "$ABM_PATH" > /dev/null 2>&1 || true
    notify-send -t 3000 -i display-brightness "ABM" "Disabled (accurate colors)"
  fi
fi
