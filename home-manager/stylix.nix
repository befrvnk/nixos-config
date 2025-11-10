{ pkgs, ... }:

{
  # Base stylix configuration (default to dark theme)
  stylix = {
    enable = true;
    autoEnable = true;
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
        package = pkgs.nerd-fonts.jetbrains-mono;
        name = "JetBrainsMono Nerd Font";
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
    # autoEnable handles most apps; explicitly disable only what's needed
    targets.anki.enable = false;
  };

  specialisation = {
    dark.configuration = {
      stylix = {
        polarity = pkgs.lib.mkForce "dark";
        base16Scheme = pkgs.lib.mkForce "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
        image = pkgs.lib.mkForce ./wallpapers/mountain.jpg;
      };
    };
    light.configuration = {
      stylix = {
        polarity = pkgs.lib.mkForce "light";
        base16Scheme = pkgs.lib.mkForce "${pkgs.base16-schemes}/share/themes/catppuccin-latte.yaml";
        image = pkgs.lib.mkForce ./wallpapers/mountain.jpg;
      };
    };
  };
}
