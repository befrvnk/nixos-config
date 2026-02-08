{
  pkgs,
  config,
  lib,
  inputs,
  ...
}:
{
  home.packages = [
    pkgs.playerctl
    pkgs.wireplumber
    pkgs.xwayland-satellite
    pkgs.brightnessctl
    pkgs.pavucontrol
    inputs.awww.packages.${pkgs.system}.awww

    # Toggle internal display on/off
    (pkgs.writeShellScriptBin "toggle-internal-display" ''
      if niri msg outputs | grep -A1 'eDP-1' | grep -q 'Disabled'; then
        niri msg output eDP-1 on
      else
        niri msg output eDP-1 off
      fi
    '')

    # Suspend with inhibitor check - notifies if a service is blocking sleep
    (pkgs.writeShellScriptBin "safe-suspend" ''
      export PATH="${pkgs.systemd}/bin:${pkgs.libnotify}/bin:${pkgs.gawk}/bin:$PATH"
      blockers=$(systemd-inhibit --list | awk '$NF == "block" && $6 ~ /sleep|handle-lid-switch/ {print $1}')
      if [[ -n "$blockers" ]]; then
        notify-send -t 5000 -i dialog-warning "Suspend Blocked" "$blockers is preventing sleep."
      else
        systemctl suspend
      fi
    '')

    # Toggle ABM (Adaptive Backlight Management) for photo editing mode
    # ABM trades color accuracy for power savings
    (pkgs.writeShellScriptBin "toggle-abm" ''
      export PATH="${pkgs.libnotify}/bin:$PATH"
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
    '')

    # Event-driven volume control (calls swayosd + updates cache for ironbar)
    # This eliminates dbus polling overhead - wpctl only runs when volume changes
    (pkgs.writeShellScriptBin "volume-ctl" ''
      export PATH="${pkgs.swayosd}/bin:${pkgs.wireplumber}/bin:${pkgs.gawk}/bin:${pkgs.gnugrep}/bin:$PATH"
      ${builtins.readFile ./volume-ctl.sh}
    '')

    # Unified brightness control for internal + external monitors
    # Internal: brightnessctl (synchronous) + swayosd OSD
    # External: syncs to internal brightness, catching up at its own pace
    (pkgs.writeShellScriptBin "brightness-ctl" ''
      export PATH="${pkgs.swayosd}/bin:${pkgs.ddcutil}/bin:${pkgs.brightnessctl}/bin:${pkgs.gawk}/bin:$PATH"

      action="$1"
      target_file="/tmp/brightness-ctl-target"
      lock_file="/tmp/brightness-ctl-ddc.lock"

      # Internal display: use brightnessctl (synchronous, no race condition)
      case "$action" in
        raise) brightnessctl -q set 5%+ ;;
        lower) brightnessctl -q set 5%- ;;
        *) echo "Usage: brightness-ctl <raise|lower>"; exit 1 ;;
      esac

      # Read current brightness percentage
      target=$(brightnessctl -m | awk -F, '{gsub(/%/,""); print $4}')

      # Show OSD with actual brightness value (0.0 to 1.0 scale)
      progress=$(awk "BEGIN {printf \"%.2f\", $target/100}")
      swayosd-client --custom-icon=display-brightness-symbolic --custom-progress="$progress"

      # Write target for external monitor
      echo "$target" > "$target_file"

      # Sync external monitor in background
      (
        # If another sync is running, it will pick up the new target when done
        if [[ -f "$lock_file" ]]; then
          exit 0
        fi

        touch "$lock_file"
        trap "rm -f '$lock_file'" EXIT

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
    '')
  ];

  # Systemd service to monitor lid switch and control internal display
  # Uses acpi_listen to detect ACPI events directly, bypassing systemd-logind
  # This works even when Happy inhibits handle-lid-switch to prevent suspend
  systemd.user.services.lid-switch-display = {
    Unit = {
      Description = "Automatic internal display control on lid switch";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.writeShellScript "lid-switch-display" (
        builtins.readFile (
          pkgs.replaceVars ./lid-switch-display.sh {
            coreutils = "${pkgs.coreutils}";
            gnugrep = "${pkgs.gnugrep}";
            gnused = "${pkgs.gnused}";
            gawk = "${pkgs.gawk}";
            niri = "${pkgs.niri}";
            acpid = "${pkgs.acpid}";
          }
        )
      )}";
      Restart = "always";
      RestartSec = "3";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Keyring is managed by PAM (see modules/desktop/greetd.nix)
  # Don't start a separate daemon here as it conflicts with PAM
  # Using mkForce to override niri-flake's default setting
  services.gnome-keyring.enable = lib.mkForce false;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      # Use GTK portal for all interfaces on Niri
      niri = {
        default = "gtk";
        "org.freedesktop.impl.portal.Settings" = "gtk";
      };
    };
  };

  # https://github.com/YaLTeR/niri/blob/main/resources/default-config.kdl
  programs.niri = {
    enable = true;
    package = pkgs.niri;

    # Configuration organized into logical modules for better readability
    settings = lib.mkMerge [
      (import ./outputs.nix { })
      (import ./inputs.nix { })
      (import ./layout.nix { inherit config; })
      (import ./rules.nix { })
      (import ./binds.nix { })
      (import ./startup.nix { inherit pkgs config inputs; })
    ];
  };
}
