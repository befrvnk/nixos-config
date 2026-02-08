{ pkgs, ... }:
{
  home.packages = [ pkgs.happy-coder ];

  systemd.user.services.happy = {
    Unit = {
      Description = "Happy remote development daemon";
      After = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=idle:sleep:handle-lid-switch --who=Happy --why='Remote development session active' ${pkgs.happy-coder}/bin/happy daemon start-sync";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };
}
