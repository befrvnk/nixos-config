{ pkgs, osConfig, ... }:
{
  spawn-at-startup = [
    { command = ["${pkgs.xwayland-satellite}/bin/xwayland-satellite"]; }
    # Start swaybg to show Stylix wallpaper on backdrop layer
    { command = [
        "${pkgs.swaybg}/bin/swaybg"
        "-i" "${osConfig.stylix.image}"
        "-m" "fill"
      ];
    }
  ];
}
