{ pkgs, ... }:

{
  # Base stylix configuration (default to dark theme)
  stylix = {
    enable = true;
    autoEnable = false;
    polarity = "dark";
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    image = ./wallpapers/mountain.jpg;

    fonts = {
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      monospace = {
        package = pkgs.nerd-fonts.fira-code;
        name = "FiraCode Nerd Font";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        applications = 11;
        terminal = 11;
        desktop = 11;
      };
    };
    cursor = {
      package = pkgs.quintom-cursor-theme;
      name = "Quintom_Snow";
      size = 24;
    };

    # Target configurations
    targets.waybar.enable = true;
    targets.anki.enable = false;
  };

  specialisation =
    let
      # Import shared theme definitions
      themes = import ./themes.nix { inherit pkgs; };
    in
    {
      dark.configuration = {
        stylix = {
          polarity = pkgs.lib.mkForce "dark";
          base16Scheme = pkgs.lib.mkForce themes.dark.scheme;
          image = pkgs.lib.mkForce themes.dark.wallpaper;
        };
      };
      light.configuration = {
        stylix = {
          polarity = pkgs.lib.mkForce "light";
          base16Scheme = pkgs.lib.mkForce themes.light.scheme;
          image = pkgs.lib.mkForce themes.light.wallpaper;
        };
      };
    };
}
