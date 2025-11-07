{
  pkgs,
  osConfig,
  lib,
  ...
}:
let
  # Reference colors from Stylix - the single source of truth
  # Stylix processes the base16 scheme and provides colors
  colors = osConfig.lib.stylix.colors;
in
{
  home.packages = [
    pkgs.playerctl
    pkgs.wireplumber
    pkgs.xwayland-satellite
    pkgs.brightnessctl
    pkgs.pavucontrol
    pkgs.swaylock
  ];
  services.gnome-keyring.enable = true;

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
      (import ./outputs.nix { inherit colors; })
      (import ./inputs.nix { })
      (import ./layout.nix { inherit colors osConfig; })
      (import ./rules.nix { })
      (import ./binds.nix { })
      (import ./startup.nix { inherit pkgs; })
    ];
  };

}
