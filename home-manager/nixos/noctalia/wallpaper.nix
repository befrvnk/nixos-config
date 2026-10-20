_:
let
  wallpapers = import ../wallpapers;
in
{
  programs.noctalia.settings = {
    wallpaper = {
      enabled = true;
      fill_mode = "crop";
      transition = [ "fade" ];
      transition_duration = 1000;
      transition_on_startup = false;
      automation.enabled = false;
      default.path = "${wallpapers.dark}";
      # Path-only favorites don't change the selected palette or theme mode.
      favorite = [
        { path = "${wallpapers.dark}"; }
        { path = "${wallpapers.light}"; }
      ];
    };
    # Niri places the ordinary wallpaper surface within its backdrop. A second
    # Noctalia backdrop would duplicate the image; keep this renderer disabled.
    backdrop = {
      enabled = false;
      blur_intensity = 0.0;
      tint_intensity = 0.0;
    };
  };
}
