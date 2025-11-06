{ pkgs, ... }:

let
  # Import shared theme definitions
  themes = import ./themes.nix { inherit pkgs; };

  # Helper function to generate Ghostty theme from base16 colors
  mkGhosttyTheme = colors: ''
    background = ${colors.base00}
    cursor-color = ${colors.base05}
    foreground = ${colors.base05}
    palette = 0=#${colors.base00}
    palette = 1=#${colors.base08}
    palette = 2=#${colors.base0B}
    palette = 3=#${colors.base0A}
    palette = 4=#${colors.base0D}
    palette = 5=#${colors.base0E}
    palette = 6=#${colors.base0C}
    palette = 7=#${colors.base05}
    palette = 8=#${colors.base03}
    palette = 9=#${colors.base08}
    palette = 10=#${colors.base0B}
    palette = 11=#${colors.base0A}
    palette = 12=#${colors.base0D}
    palette = 13=#${colors.base0E}
    palette = 14=#${colors.base0C}
    palette = 15=#${colors.base07}
    selection-background = ${colors.base02}
    selection-foreground = ${colors.base05}
  '';
in
{
  # Disable stylix's automatic Ghostty theming since we handle it manually
  stylix.targets.ghostty.enable = false;

  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;

    # Use Ghostty's native light/dark theme switching
    # Ghostty will automatically switch based on desktop environment appearance
    settings = {
      theme = "light:stylix-light,dark:stylix-dark";
    };
  };

  # Generate BOTH theme files in every configuration
  # This prevents home-manager from deleting one when switching specialisations
  # Themes are defined in themes.nix - change colors there to switch themes
  home.file.".config/ghostty/themes/stylix-light".text = mkGhosttyTheme themes.light.colors;

  home.file.".config/ghostty/themes/stylix-dark".text = mkGhosttyTheme themes.dark.colors;

  # Force overwrite the config file to prevent conflicts
  xdg.configFile."ghostty/config".force = true;
}
