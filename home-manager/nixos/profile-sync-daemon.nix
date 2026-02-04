{
  pkgs,
  ...
}:

let
  psdConf = ''
    # Profile-sync-daemon configuration
    # Managed by NixOS home-manager

    # Use overlayfs for better performance and reduced memory footprint
    # Requires sudo access configured via psd helper
    USE_OVERLAYFS="no"

    # Browsers to sync - Zen Browser support added via overlay
    BROWSERS=(zen)

    # Enable crash recovery backups
    USE_BACKUPS="yes"

    # Keep last 3 crash recovery snapshots
    BACKUP_LIMIT=3
  '';
in
{
  # profile-sync-daemon with Zen Browser support (added via overlay)
  home.packages = [ pkgs.profile-sync-daemon ];

  # Create psd configuration
  xdg.configFile."psd/psd.conf".text = psdConf;

  # Systemd user services and timers for profile-sync-daemon
  systemd.user = {
    services = {
      # Main psd service
      psd = {
        Unit = {
          Description = "Profile-sync-daemon";
          Documentation = "man:psd(1)";
          Wants = [ "psd-resync.timer" ];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = "yes";
          ExecStart = "${pkgs.profile-sync-daemon}/bin/psd sync";
          ExecStop = "${pkgs.profile-sync-daemon}/bin/psd unsync";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };
      };

      # Resync service triggered by timer
      psd-resync = {
        Unit = {
          Description = "Profile-sync-daemon resync";
          After = [ "psd.service" ];
          Wants = [ "psd-resync.timer" ];
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.profile-sync-daemon}/bin/psd resync";
        };
      };
    };

    # Timer for periodic resync (every 10 minutes)
    timers.psd-resync = {
      Unit = {
        Description = "Profile-sync-daemon resync timer";
      };
      Timer = {
        OnUnitActiveSec = "10m";
      };
      Install = {
        WantedBy = [ "timers.target" ];
      };
    };
  };
}
