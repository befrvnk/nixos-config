{ colors, osConfig, ... }:
{
  cursor = {
    theme = "default";
    size = 24;
    hide-when-typing = true;
  };

  prefer-no-csd = true;

  overview = {
    backdrop-color = "#${colors.base02}";
    zoom = 0.5;
  };

  layout = {
    gaps = 12;
    struts = {
      left = 0;
      right = 0;
      top = 0;
      bottom = 0;
    };
    focus-ring = {
      enable = true;
      width = 3;
      active.color = "#${colors.base0D}";
    };
    border = {
      enable = true;
      width = 3;
      active.color = "#${colors.base03}";
      inactive.color = "#${colors.base03}";
    };
    default-column-width = {
      proportion = osConfig.defaults.display.defaultColumnWidthPercent;
    };
    preset-column-widths = map (width: { proportion = width; }) osConfig.defaults.display.columnWidthPercentPresets;
  };
}
