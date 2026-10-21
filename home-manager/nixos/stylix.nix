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
      # No configured consumers: don't create dormant mode-specific assets or
      # inject a KDE look-and-feel directory into this Niri/qtct session.
      blender.enable = false;
      forge.enable = false;
      gdu.enable = false;
      gedit.enable = false;
      kde.enable = false;
      vencord.enable = false;
      # Native Noctalia renders Zen's pinned community CSS.
      zen-browser.enable = false;
    };
  };

  # GTK icon theme
  gtk = {
    # Keep GTK4 on libadwaita; Noctalia supplies colors through its CSS import.
    gtk4.theme = pkgs.lib.mkForce null;
    iconTheme = {
      package = pkgs.papirus-icon-theme;
      name = "Papirus";
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
