{ ... }:
{
  window-rules = [
    {
      draw-border-with-background = false;
      geometry-corner-radius = {
        top-left = 16.0;
        top-right = 16.0;
        bottom-left = 16.0;
        bottom-right = 16.0;
      };
      clip-to-geometry = true;
    }
    {
      matches = [ { app-id = "^signal$"; } ];
      open-floating = true;
      default-column-width.fixed = 1000;
      default-window-height.fixed = 600;
    }
    {
      matches = [ { app-id = "^ZapZap$"; } ];
      open-floating = true;
      default-column-width.fixed = 1000;
      default-window-height.fixed = 600;
    }
    {
      matches = [ { app-id = "^1password$"; } ];
      open-floating = true;
    }
    {
      matches = [
        {
          app-id = "zen-beta";
        }
      ];
      default-column-width.proportion = 0.75;
    }
    {
      matches = [
        {
          app-id = "^zen-beta$";
          title = "^Picture-in-Picture$";
        }
      ];
      open-floating = true;
    }
    {
      matches = [
        {
          app-id = "org.gnome.NautilusPreviewer";
        }
      ];
      open-floating = true;
      default-column-width.proportion = 0.5;
      default-window-height.proportion = 0.5;
    }
    {
      matches = [ { is-floating = true; } ];
      geometry-corner-radius = {
        top-left = 16.0;
        top-right = 16.0;
        bottom-left = 16.0;
        bottom-right = 16.0;
      };
    }
  ];

  layer-rules = [
    {
      matches = [ { namespace = "notifications"; } ];
      block-out-from = "screen-capture";
    }
    # Place awww wallpaper on backdrop layer (visible in overview mode)
    {
      matches = [ { namespace = "awww-daemon"; } ];
      place-within-backdrop = true;
    }
  ];
}
