{ ... }:
{
  outputs = {
    "eDP-1" = {
      scale = 1.40;
    };
    "DP-3" = {
      scale = 1.25;
      mode = {
        width = 3840;
        height = 2160;
        refresh = 120.0;
      };
    };
  };
}
