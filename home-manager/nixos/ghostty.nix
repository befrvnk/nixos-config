{ pkgs, ... }:

let
  themes = import ../../shared/themes.nix { inherit pkgs; };

  # Parse base16 scheme YAML to get color values
  parseBase16Scheme =
    schemeFile:
    let
      jsonFile = pkgs.runCommand "base16-to-json" { } ''
        ${pkgs.yq-go}/bin/yq -o json ${schemeFile} > $out
      '';
    in
    builtins.fromJSON (builtins.readFile jsonFile);

  # Colors are now dynamically loaded from themes.nix
  darkColors = (parseBase16Scheme themes.dark.base16Scheme).palette;
  lightColors = (parseBase16Scheme themes.light.base16Scheme).palette;

  # Helper to convert base16 colors to Ghostty theme format
  # Note: base16 colors already include '#' prefix
  mkGhosttyTheme = colors: ''
    background = ${colors.base00}
    cursor-color = ${colors.base05}
    foreground = ${colors.base05}
    palette = 0=${colors.base00}
    palette = 1=${colors.base08}
    palette = 2=${colors.base0B}
    palette = 3=${colors.base0A}
    palette = 4=${colors.base0D}
    palette = 5=${colors.base0E}
    palette = 6=${colors.base0C}
    palette = 7=${colors.base05}
    palette = 8=${colors.base03}
    palette = 9=${colors.base08}
    palette = 10=${colors.base0B}
    palette = 11=${colors.base0A}
    palette = 12=${colors.base0D}
    palette = 13=${colors.base0E}
    palette = 14=${colors.base0C}
    palette = 15=${colors.base07}
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
