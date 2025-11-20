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
