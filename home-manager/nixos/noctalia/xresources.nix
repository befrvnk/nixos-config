{
  config,
  lib,
  pkgs,
  ...
}:
let
  colors = "${config.xdg.stateHome}/noctalia/Xresources";
  fonts = config.stylix.fonts;
  apply = pkgs.writeShellScript "noctalia-xresources-apply" ''
    if [[ -n "''${DISPLAY:-}" ]]; then
      ${pkgs.xrdb}/bin/xrdb -merge ${lib.escapeShellArg config.xresources.path}
    fi
  '';
in
{
  # Neither pinned catalog has Xresources. Keep shared X11 fonts/cursor static
  # and render color data only; xterm is installed and uses the live resource DB.
  stylix.targets = {
    sxiv.enable = false;
    xresources.enable = false;
  };
  xresources = {
    extraConfig = ''#include "${colors}"'';
    properties = {
      "*.faceName" = fonts.monospace.name;
      "*.faceSize" = toString fonts.sizes.terminal;
      "*.renderFont" = true;
      "Sxiv.font" = "${fonts.sansSerif.name}-${toString fonts.sizes.applications}";
      "Xcursor.size" = config.stylix.cursor.size;
      "Xcursor.theme" = config.stylix.cursor.name;
    };
  };

  programs.noctalia.settings.theme.templates.user.xresources = {
    input_path = "${./xresources.template}";
    output_path = "$XDG_STATE_HOME/noctalia/Xresources";
    post_hook = "${apply}";
  };

  noctalia.prepareOutputs = [
    {
      theme = colors;
      backup = "${config.xdg.stateHome}/noctalia/xresources.pre-template";
      placeholder = "! Awaiting Noctalia X11 colors.";
    }
  ];
}
