{ pkgs }:

{
  # Define dark and light base16 color schemes
  # These are used by both Stylix and Zen Browser
  dark = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
    polarity = "dark";
  };

  light = {
    base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-latte.yaml";
    polarity = "light";
  };
}
