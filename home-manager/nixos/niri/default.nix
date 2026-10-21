{
  config,
  pkgs,
  lib,
  ...
}:
{
  home.packages = [
    pkgs.playerctl
    pkgs.wireplumber
    pkgs.xwayland-satellite
    pkgs.brightnessctl
    pkgs.pavucontrol

    # Toggle internal display on/off
    (pkgs.writeShellScriptBin "toggle-internal-display" ''
      if niri msg outputs | grep -A1 'eDP-1' | grep -q 'Disabled'; then
        niri msg output eDP-1 on
      else
        niri msg output eDP-1 off
      fi
    '')

    # Query structured logind data; idle/lid-only locks do not veto manual sleep.
    (pkgs.writeShellScriptBin "safe-suspend" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.systemd
          pkgs.libnotify
          pkgs.jq
        ]
      }"
      ${builtins.readFile ./safe-suspend.sh}
    '')

    # Toggle ABM (Adaptive Backlight Management) for photo editing mode
    # ABM trades color accuracy for power savings
    (pkgs.writeShellScriptBin "toggle-abm" ''
      export PATH="${pkgs.libnotify}/bin:$PATH"
      ${builtins.readFile ./toggle-abm.sh}
    '')

    # Unified brightness control for internal + external monitors
    # Internal: brightnessctl (synchronous) + native display-only Noctalia OSD
    # External: syncs to internal brightness, catching up at its own pace
    (pkgs.writeShellScriptBin "brightness-ctl" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.brightnessctl
          pkgs.coreutils
          pkgs.ddcutil
          pkgs.gawk
          config.programs.noctalia.package
        ]
      }"
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
      (import ./layout.nix { })
      (import ./rules.nix { })
      (import ./binds.nix { inherit config; })
      (import ./startup.nix { inherit pkgs; })
    ];
  };
}
