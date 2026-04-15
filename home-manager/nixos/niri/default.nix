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
    inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww

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
      ${builtins.readFile ./toggle-abm.sh}
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
      ${builtins.readFile ./brightness-ctl.sh}
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
