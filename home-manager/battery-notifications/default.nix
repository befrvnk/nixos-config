{ pkgs, ... }:

let
  # Python script for battery monitoring
  batteryMonitorScript = pkgs.writeScript "battery-monitor" ''
    #!${pkgs.python3}/bin/python3
    ${builtins.readFile ./battery-monitor.py}
  '';
in
{
  # Battery notification service
  # Monitors battery levels and sends notifications for:
  # - 5% battery (critical) when discharging
  # - 20% battery (low) when discharging
  # - 100% battery (full) when charging
  systemd.user.services.battery-notifications = {
    Unit = {
      Description = "Battery level notifications";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${batteryMonitorScript}";
      Restart = "always";
      RestartSec = "10";
      # Ensure the script has access to required commands
      Environment = [
        "PATH=${pkgs.upower}/bin:${pkgs.libnotify}/bin"
      ];
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
