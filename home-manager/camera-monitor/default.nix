{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.camera-monitor;

  # Python environment with required dependencies
  pythonEnv = pkgs.python3.withPackages (
    ps: with ps; [
      requests
      beautifulsoup4
    ]
  );

  # The monitoring script
  monitorScript = pkgs.writeScriptBin "camera-monitor" ''
    #!${pythonEnv}/bin/python3
    ${builtins.readFile ./monitor.py}
  '';
in
{
  options.services.camera-monitor = {
    enable = lib.mkEnableOption "Fujifilm X-T50 camera availability monitor";

    interval = lib.mkOption {
      type = lib.types.str;
      default = "*:00/30";
      description = ''
        How often to check camera availability (systemd timer format).
        Default is every 30 minutes at :00 and :30.
      '';
      example = "*:15:00";
    };
  };

  config = lib.mkIf cfg.enable {
    # Install notify-send for notifications
    home.packages = [ pkgs.libnotify ];

    # Systemd user service
    systemd.user.services.camera-monitor = {
      Unit = {
        Description = "Fujifilm X-T50 Camera Availability Monitor";
        After = [ "network-online.target" ];
      };

      Service = {
        Type = "oneshot";
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 15"; # Wait for network after resume
        ExecStart = "${monitorScript}/bin/camera-monitor";

        # Environment variables needed for notifications
        Environment = [
          "DISPLAY=:0"
          "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%U/bus"
        ];

        # Restart policy
        Restart = "no"; # Don't restart on failure (timer will retry)
      };
    };

    # Systemd user timer
    systemd.user.timers.camera-monitor = {
      Unit = {
        Description = "Timer for Fujifilm X-T50 Camera Availability Monitor";
      };

      Timer = {
        OnCalendar = cfg.interval;
        Persistent = false; # Don't run missed checks after suspend/resume
        Unit = "camera-monitor.service";
      };

      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
