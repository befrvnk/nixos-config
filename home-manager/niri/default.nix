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
  ];
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
