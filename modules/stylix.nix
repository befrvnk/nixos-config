{ pkgs, ... }:

{
  # Minimal system-level stylix configuration
  # The actual theming is handled by home-manager specialisations
  stylix = {
    enable = true;
    autoEnable = true;
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    image = pkgs.fetchurl {
      url = "https://raw.githubusercontent.com/catppuccin/wallpapers/main/minimalistic/catppuccin_triangle.png";
      hash = "sha256-/Az/W0X/DRbLW96Hev0MmOECOZ0KKFGj5MzXkALWRXk=";
    };

    # Disable automatic home-manager integration since we're manually importing it
    homeManagerIntegration = {
      autoImport = false;
      followSystem = false;
    };
  };
}
