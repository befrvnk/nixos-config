{ ... }:
{
  window-rules = [
    {
      draw-border-with-background = false;
      geometry-corner-radius = {
        top-left = 8.0;
        top-right = 8.0;
        bottom-left = 8.0;
        bottom-right = 8.0;
      };
      clip-to-geometry = true;
    }
    {
      matches = [{ is-floating = true; }];
      geometry-corner-radius = {
        top-left = 16.0;
        top-right = 16.0;
        bottom-left = 16.0;
        bottom-right = 16.0;
      };
    }
    {
      matches = [{ is-active = false; }];
      opacity = 0.99;
    }
  ];

  layer-rules = [
    {
      matches = [{ namespace = "notifications"; }];
      block-out-from = "screen-capture";
    }
    # Place swaybg wallpaper on backdrop layer (visible in overview mode)
    {
      matches = [{ namespace = "wallpaper"; }];
      place-within-backdrop = true;
    }
  ];
}
