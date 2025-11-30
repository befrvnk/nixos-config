{ pkgs, ... }:

let
  wallpapers = import ./wallpapers;
  themes = import ./themes.nix { inherit pkgs; };
in
{
  # Base stylix configuration (default to dark theme)
  stylix = {
    enable = true;
    autoEnable = true;
    polarity = themes.dark.polarity;
    base16Scheme = themes.dark.base16Scheme;
    image = wallpapers.dark;

    # Disable version check warnings (we use nixpkgs-unstable for everything)
    enableReleaseChecks = false;

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
    targets = {
      anki.enable = false;
      # Disable Stylix auto-generation for Zen Browser - we manage manually with media queries
      zen-browser.enable = false;
    };
  };

  specialisation = {
    dark.configuration = {
      stylix = {
        polarity = pkgs.lib.mkForce themes.dark.polarity;
        base16Scheme = pkgs.lib.mkForce themes.dark.base16Scheme;
        image = pkgs.lib.mkForce wallpapers.dark;
      };
    };
    light.configuration = {
      stylix = {
        polarity = pkgs.lib.mkForce themes.light.polarity;
        base16Scheme = pkgs.lib.mkForce themes.light.base16Scheme;
        image = pkgs.lib.mkForce wallpapers.light;
      };
    };
  };
}
