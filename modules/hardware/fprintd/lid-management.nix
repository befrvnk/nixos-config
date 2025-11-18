{ pkgs, ... }:

{
  # Systemd service to manage fprintd based on lid state
  # Stops fprintd when lid is closed, starts it when opened
  systemd.services.fprintd-lid-manager = {
    description = "Manage fprintd service based on laptop lid state";
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "5s";
      ExecStart = "${pkgs.bash}/bin/bash ${./lid-monitor.sh}";
      Environment = "PATH=${pkgs.gawk}/bin:${pkgs.coreutils}/bin:${pkgs.systemd}/bin";
    };
  };
}
