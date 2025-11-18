{ pkgs, ... }:

let
  # Shell script for battery monitoring (uses upower --monitor-detail)
  # This is event-driven and maintains a single persistent D-Bus connection
  batteryMonitorScript = pkgs.writeShellScript "battery-monitor" ''
    # Ensure required commands are in PATH
    export PATH="${pkgs.upower}/bin:${pkgs.libnotify}/bin:${pkgs.gawk}/bin:${pkgs.coreutils}/bin:${pkgs.gnugrep}/bin:$PATH"

    ${builtins.readFile ./battery-monitor.sh}
  '';
in
{
  # Battery notification service (event-driven shell script)
  # Monitors battery levels and sends notifications for:
  # - 5% battery (critical) when discharging
  # - 20% battery (low) when discharging
  # - 100% battery (full) when charging
  #
  # Uses 'upower --monitor-detail' which maintains a single persistent D-Bus connection
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
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
