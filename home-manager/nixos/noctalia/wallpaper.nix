{
  config,
  lib,
  pkgs,
  ...
}:
let
  wallpapers = import ../wallpapers;
  selectMode = pkgs.writeShellScript "noctalia-wallpaper-mode" (
    lib.replaceStrings
      [ "@coreutils@" "@dark@" "@light@" "@noctalia@" "@util_linux@" ]
      [
        "${pkgs.coreutils}"
        (lib.escapeShellArg "${wallpapers.dark}")
        (lib.escapeShellArg "${wallpapers.light}")
        (lib.escapeShellArg (lib.getExe config.programs.noctalia.package))
        "${pkgs.util-linux}"
      ]
      (builtins.readFile ./wallpaper-mode.sh)
  );
in
{
  programs.noctalia.settings = {
    hooks = {
      started = lib.mkBefore [ "${selectMode}" ];
      theme_mode_changed = lib.mkBefore [ "${selectMode}" ];
    };
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
