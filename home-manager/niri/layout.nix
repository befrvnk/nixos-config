{ osConfig, ... }:
let
  inherit (osConfig.lib.stylix.colors.withHashtag) base0D base03 base08;
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
      enable = true;
      width = 3;
      active.color = base0D;
      inactive.color = base03;
      urgent.color = base08;
    };
    border = {
      enable = true;
      width = 2;
      active.color = "transparent";
      inactive.color = "transparent";
    };
    default-column-width = {
      proportion = osConfig.defaults.display.defaultColumnWidthPercent;
    };
    preset-column-widths = map (width: {
      proportion = width;
    }) osConfig.defaults.display.columnWidthPercentPresets;
  };
}
