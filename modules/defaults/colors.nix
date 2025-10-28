{
  pkgs,
  lib,
  ...
}:
with lib; {
  options.defaults = {
    colorScheme = mkOption {
      type = types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            description = "Color scheme name";
          };
          palette = mkOption {
            type = types.attrs;
            description = "Color palette configuration";
          };
        };
      };
      description = "Color scheme configuration following base16 scheme";
    };
  };

  config = {
    defaults = {
      # Custom purple/pink color scheme
      # https://github.com/tinted-theming/schemes
      colorScheme = {
        name = "custom";
        palette = {
          base00 = "191033"; # Default Background
          base01 = "1e133c"; # Lighter Background
          base02 = "2f235c"; # Selection Background
          base03 = "404079"; # Comments, Invisibles
          base04 = "646499"; # Dark Foreground
          base05 = "f8f8f8"; # Default Foreground
          base06 = "e5e4fb"; # Light Foreground
          base07 = "fad000"; # Light Background
          base08 = "ff628c"; # Variables, Tags (Pink)
          base09 = "ffb454"; # Integers, Constants (Orange)
          base0A = "ffee80"; # Classes (Yellow)
          base0B = "a5ff90"; # Strings (Green)
          base0C = "80fcff"; # Support, Regex (Cyan)
          base0D = "fad000"; # Functions, Methods (Yellow)
          base0E = "faefa5"; # Keywords, Storage (Light Yellow)
          base0F = "fb94ff"; # Diff Changed (Purple)
        };
      };
    };
  };
}
