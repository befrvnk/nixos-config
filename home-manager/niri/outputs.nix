{ colors, ... }:
{
  outputs = {
    "eDP-1" = {
      scale = 1.25;
      background-color = "#${colors.base02}";
    };
    "DP-3" = {
      scale = 1.25;
      variable-refresh-rate = "on-demand";
      background-color = "#${colors.base02}";
    };
  };
}
