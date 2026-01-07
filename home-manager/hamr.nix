{
  config,
  pkgs,
  ...
}:

let
  colors = config.lib.stylix.colors.withHashtag;

  # Generate Material Design 3 colors from Stylix base16 scheme
  # base00 = background, base05 = text (works for both light and dark)
  # All "on_*" colors should use base05 (text) for readability
  generateColorsJson = ''
    {
      "background": "${colors.base00}",
      "on_background": "${colors.base05}",
      "surface": "${colors.base00}",
      "surface_dim": "${colors.base01}",
      "surface_bright": "${colors.base02}",
      "surface_container_lowest": "${colors.base01}",
      "surface_container_low": "${colors.base01}",
      "surface_container": "${colors.base02}",
      "surface_container_high": "${colors.base03}",
      "surface_container_highest": "${colors.base04}",
      "on_surface": "${colors.base05}",
      "surface_variant": "${colors.base02}",
      "on_surface_variant": "${colors.base05}",
      "inverse_surface": "${colors.base05}",
      "inverse_on_surface": "${colors.base00}",
      "outline": "${colors.base05}",
      "outline_variant": "${colors.base04}",
      "shadow": "#000000",
      "scrim": "#000000",
      "surface_tint": "${colors.base0D}",
      "primary": "${colors.base0D}",
      "on_primary": "${colors.base00}",
      "primary_container": "${colors.base02}",
      "on_primary_container": "${colors.base05}",
      "inverse_primary": "${colors.base0D}",
      "secondary": "${colors.base0C}",
      "on_secondary": "${colors.base00}",
      "secondary_container": "${colors.base02}",
      "on_secondary_container": "${colors.base05}",
      "tertiary": "${colors.base0E}",
      "on_tertiary": "${colors.base00}",
      "tertiary_container": "${colors.base02}",
      "on_tertiary_container": "${colors.base05}",
      "error": "${colors.base08}",
      "on_error": "${colors.base00}",
      "error_container": "${colors.base02}",
      "on_error_container": "${colors.base08}",
      "primary_fixed": "${colors.base0D}",
      "primary_fixed_dim": "${colors.base0D}",
      "on_primary_fixed": "${colors.base05}",
      "on_primary_fixed_variant": "${colors.base05}",
      "secondary_fixed": "${colors.base0C}",
      "secondary_fixed_dim": "${colors.base0C}",
      "on_secondary_fixed": "${colors.base05}",
      "on_secondary_fixed_variant": "${colors.base05}",
      "tertiary_fixed": "${colors.base0E}",
      "tertiary_fixed_dim": "${colors.base0E}",
      "on_tertiary_fixed": "${colors.base05}",
      "on_tertiary_fixed_variant": "${colors.base05}",
      "success": "${colors.base0B}",
      "on_success": "${colors.base00}",
      "success_container": "${colors.base02}",
      "on_success_container": "${colors.base05}"
    }
  '';
in
{
  programs.hamr.enable = true;

  # Generate colors.json from current Stylix theme
  # This file is auto-watched by hamr and reloaded on change
  xdg.configFile."hamr/colors.json".text = generateColorsJson;
}
