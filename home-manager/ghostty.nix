{ pkgs, ... }:

let
  # Catppuccin Mocha colors (must match stylix dark theme)
  darkColors = {
    base00 = "1e1e2e";
    base01 = "181825";
    base02 = "313244";
    base03 = "45475a";
    base04 = "585b70";
    base05 = "cdd6f4";
    base06 = "f5e0dc";
    base07 = "b4befe";
    base08 = "f38ba8";
    base09 = "fab387";
    base0A = "f9e2af";
    base0B = "a6e3a1";
    base0C = "94e2d5";
    base0D = "89b4fa";
    base0E = "cba6f7";
    base0F = "f2cdcd";
  };

  # Catppuccin Latte colors (must match stylix light theme)
  lightColors = {
    base00 = "eff1f5";
    base01 = "e6e9ef";
    base02 = "ccd0da";
    base03 = "bcc0cc";
    base04 = "acb0be";
    base05 = "4c4f69";
    base06 = "dc8a78";
    base07 = "7287fd";
    base08 = "d20f39";
    base09 = "fe640b";
    base0A = "df8e1d";
    base0B = "40a02b";
    base0C = "179299";
    base0D = "1e66f5";
    base0E = "8839ef";
    base0F = "dd7878";
  };

  # Helper to convert base16 colors to Ghostty theme format
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
  # Disable Stylix's automatic Ghostty theming
  stylix.targets.ghostty.enable = false;

  programs.ghostty = {
    enable = true;
    package = pkgs.ghostty;

    # Use Ghostty's automatic theme switching based on system appearance
    settings = {
      theme = "light:stylix-light,dark:stylix-dark";

      # Fix Shift+Enter for Claude Code
      # https://github.com/anthropics/claude-code/issues/1282
      keybind = [
        "shift+enter=text:\\x1b\\r"
      ];

      # Note: Ctrl+Left/Right word jumping is configured at the shell level
      # in zsh/keybindings.zsh instead of here, as recommended by Ghostty docs
    };
  };

  # Generate BOTH theme files in every configuration
  home.file.".config/ghostty/themes/stylix-light".text = mkGhosttyTheme lightColors;
  home.file.".config/ghostty/themes/stylix-dark".text = mkGhosttyTheme darkColors;

  # Force overwrite the config file to prevent conflicts
  xdg.configFile."ghostty/config".force = true;
}
