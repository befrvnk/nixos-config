{ pkgs, ... }:
{
  spawn-at-startup = [
    { command = ["${pkgs.xwayland-satellite}/bin/xwayland-satellite"]; }
  ];
}
