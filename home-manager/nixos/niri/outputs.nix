{ ... }:
{
  outputs = {
    "eDP-1" = {
      scale = 1.40;
      variable-refresh-rate = true;
    };
    "DP-3" = {
      scale = 1.25;
      variable-refresh-rate = true;
      mode = {
        width = 3840;
        height = 2160;
        refresh = 120.0;
      };
    };
  };
}
