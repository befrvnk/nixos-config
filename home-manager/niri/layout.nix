{ config, ... }:
let
  inherit (config.lib.stylix.colors.withHashtag) base0D;
in
{
  cursor = {
    theme = "default";
    size = 24;
    hide-when-typing = true;
  };

  prefer-no-csd = true;

  overview = {
    zoom = 0.5;
    workspace-shadow = {
      enable = false;
    };
  };

  layout = {
    gaps = 12;
    # Transparent workspace backgrounds allow the wallpaper backdrop to show through
    background-color = "transparent";
    struts = {
      left = 0;
      right = 0;
      top = 0;
      bottom = 0;
    };
    focus-ring = {
      enable = false;
    };
    border = {
      enable = true;
      width = 4;
      active.color = base0D;
      inactive.color = "transparent";
    };
    default-column-width = {
      proportion = 0.5;
    };
    preset-column-widths =
      map
        (width: {
          proportion = width;
        })
        [
          0.75
          0.5
          0.25
        ];
  };
}
