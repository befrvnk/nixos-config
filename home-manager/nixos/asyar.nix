{ pkgs, ... }:
let
  asyarPkg = pkgs.callPackage ../../pkgs/asyar { };
in
{
  home.packages = [ asyarPkg ];

  systemd.user.services.asyar = {
    Unit = {
      Description = "Asyar application launcher";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };
    Service = {
      ExecStart = "${asyarPkg}/bin/asyar";
      Restart = "on-failure";
      RestartSec = "3";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
