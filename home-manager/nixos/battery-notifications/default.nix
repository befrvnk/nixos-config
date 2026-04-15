{ lib, pkgs, ... }:

let
  hmLib = import ../lib.nix { inherit lib pkgs; };

  # Shell script for battery monitoring (uses upower --monitor-detail)
  # This is event-driven and maintains a single persistent D-Bus connection
  batteryMonitorScript = hmLib.mkPathWrappedScript {
    name = "battery-monitor";
    packages = [
      pkgs.upower
      pkgs.libnotify
      pkgs.gawk
      pkgs.coreutils
      pkgs.gnugrep
    ];
    script = ./battery-monitor.sh;
  };
in
{
  # Battery notification service (event-driven shell script)
  # Monitors battery levels and sends notifications for:
  # - 5% battery (critical) when discharging
  # - 20% battery (low) when discharging
  # - 100% battery (full) when charging
  #
  # Uses 'upower --monitor-detail' which maintains a single persistent D-Bus connection
  systemd.user.services.battery-notifications = hmLib.mkGraphicalUserService {
    description = "Battery level notifications";
    execStart = "${batteryMonitorScript}";
    restartSec = "10";
  };
}
