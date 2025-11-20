{
  pkgs,
  config,
  inputs,
  ...
}:
{
  spawn-at-startup = [
    { command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ]; }
    # Start awww daemon for wallpaper management with fade transitions
    {
      command = [
        "${inputs.awww.packages.${pkgs.system}.awww}/bin/awww-daemon"
      ];
    }
  ];
}
