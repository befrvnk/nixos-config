{ config, pkgs, ... }:

let
  # Auto-brightness script that reads IIO sensor and sets backlight
  autoBrightnessScript = pkgs.writeShellScript "auto-brightness" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.brightnessctl}/bin:$PATH"

    SENSOR="/sys/bus/iio/devices/iio:device0/in_illuminance_raw"
    MIN_BRIGHTNESS=5
    MAX_BRIGHTNESS=100
    LAST_LUX=-1
    HYSTERESIS=3

    # Map lux to brightness percentage (piecewise linear)
    # Thresholds: 0-20 lux = 5-20%, 20-100 lux = 20-50%, 100-500 lux = 50-80%, 500+ = 80-100%
    lux_to_brightness() {
      local lux=$1
      if [ "$lux" -le 20 ]; then
        echo $((5 + lux * 15 / 20))
      elif [ "$lux" -le 100 ]; then
        echo $((20 + (lux - 20) * 30 / 80))
      elif [ "$lux" -le 500 ]; then
        echo $((50 + (lux - 100) * 30 / 400))
      else
        echo $((80 + (lux - 500) * 20 / 500))
      fi
    }

    clamp() {
      local val=$1
      [ "$val" -lt "$MIN_BRIGHTNESS" ] && val=$MIN_BRIGHTNESS
      [ "$val" -gt "$MAX_BRIGHTNESS" ] && val=$MAX_BRIGHTNESS
      echo "$val"
    }

    while true; do
      if [ -f "$SENSOR" ]; then
        LUX=$(cat "$SENSOR" 2>/dev/null || echo "$LAST_LUX")

        # Only update if lux changed beyond hysteresis
        if [ "$LAST_LUX" -eq -1 ] || [ $((LUX - LAST_LUX)) -gt $HYSTERESIS ] || [ $((LAST_LUX - LUX)) -gt $HYSTERESIS ]; then
          BRIGHTNESS=$(lux_to_brightness "$LUX")
          BRIGHTNESS=$(clamp "$BRIGHTNESS")
          brightnessctl set "''${BRIGHTNESS}%" -q
          LAST_LUX=$LUX
        fi
      fi
      sleep 1
    done
  '';

  # Toggle script for photo editing mode (disables auto-brightness and ABM)
  toggleScript = pkgs.writeShellScript "toggle-auto-brightness" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.systemd}/bin:${pkgs.libnotify}/bin:$PATH"

    SERVICE="auto-brightness.service"
    ABM_PATH="/sys/class/drm/card1-eDP-1/amdgpu/panel_power_savings"
    STATE_FILE="$HOME/.local/state/auto-brightness-enabled"

    mkdir -p "$(dirname "$STATE_FILE")"

    if systemctl --user is-active "$SERVICE" &>/dev/null; then
      # Currently enabled -> disable for photo editing
      systemctl --user stop "$SERVICE"
      echo 0 | tee "$ABM_PATH" > /dev/null 2>&1 || true
      echo "disabled" > "$STATE_FILE"
      notify-send -t 3000 -i display-brightness "Auto Brightness" "Disabled (photo editing mode)"
    else
      # Currently disabled -> enable
      systemctl --user start "$SERVICE"
      # ABM will be set by power-profile-auto based on AC/battery state
      echo "enabled" > "$STATE_FILE"
      notify-send -t 3000 -i display-brightness "Auto Brightness" "Enabled"
    fi
  '';
in
{
  home.packages = [
    (pkgs.writeShellScriptBin "toggle-auto-brightness" ''
      exec ${toggleScript}
    '')
  ];

  systemd.user.services.auto-brightness = {
    Unit = {
      Description = "Automatic brightness adjustment based on ambient light sensor";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${autoBrightnessScript}";
      Restart = "on-failure";
      RestartSec = "5";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
