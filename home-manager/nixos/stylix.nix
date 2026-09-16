{ pkgs, ... }:

let
  wallpapers = import ./wallpapers;
  themes = import ../../shared/themes.nix { inherit pkgs; };
in
{
  # Base stylix configuration (default to dark theme)
  stylix = {
    enable = true;
    autoEnable = true;
    inherit (themes.dark) polarity base16Scheme;
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
      qt.enable = pkgs.lib.mkForce false;
      # Disable Stylix auto-generation for Zen Browser - we manage manually with media queries
      zen-browser.enable = false;
    };
  };

  # GTK icon theme
  gtk = {
    # Keep GTK4 on libadwaita; override Stylix's generated GTK4 theme.
    gtk4.theme = pkgs.lib.mkForce null;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus";
    };
  };

  home.file.".config/qt5ct/qt5ct.conf".text = ''
    [Appearance]
    icon_theme=Papirus
    style=kvantum
    [Fonts]
    fixed="JetBrainsMono Nerd Font,11"
    general="Noto Sans,11"
  '';
  home.file.".config/qt6ct/qt6ct.conf".text = ''
    [Appearance]
    icon_theme=Papirus
    style=kvantum
    [Fonts]
    fixed="JetBrainsMono Nerd Font,11"
    general="Noto Sans,11"
  '';

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
