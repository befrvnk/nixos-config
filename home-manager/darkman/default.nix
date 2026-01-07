{
  config,
  pkgs,
  inputs,
  ...
}:

let
  wallpapers = import ../wallpapers;
in
{
  # Darkman configuration
  home.file.".config/darkman/config.yaml".text = ''
    lat: 48.13743
    lng: 11.57549
  '';

  # Restart darkman after home-manager activation to re-evaluate current theme
  # Only restart if we're not already being run by darkman (avoid infinite loop)
  home.activation.restartDarkman = config.lib.dag.entryAfter [ "writeBoundary" ] ''
    # Check if DARKMAN_RUNNING environment variable is set
    # Use parameter expansion with default to avoid "unbound variable" error
    if [ -z "''${DARKMAN_RUNNING:-}" ]; then
      $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart darkman.service || true

      # After restart, wait for awww-daemon to be ready and apply initial wallpaper
      # This ensures wallpaper is set on boot and after home-manager switches
      if [ -z "$DRY_RUN_CMD" ]; then
        for i in {1..10}; do
          if ${inputs.awww.packages.${pkgs.system}.awww}/bin/awww query &>/dev/null; then
            MODE=$(${pkgs.darkman}/bin/darkman get) || MODE="dark"
            ~/.local/share/darkman-switch-mode.sh "$MODE" &>/dev/null || true
            break
          fi
          sleep 0.5
        done &
      fi
    fi
  '';

  # Darkman scripts for theme switching
  # Note: darkman looks for scripts in XDG_DATA_HOME/light-mode.d and XDG_DATA_HOME/dark-mode.d
  # NOT in a darkman subdirectory!

  # Unified theme switching script
  home.file.".local/share/darkman-switch-mode.sh" = {
    source = pkgs.replaceVars ./darkman-switch-mode.sh {
      dconf = "${pkgs.dconf}";
      systemd = "${pkgs.systemd}";
      niri = "${pkgs.niri}";
      coreutils = "${pkgs.coreutils}";
      gnugrep = "${pkgs.gnugrep}";
      gnused = "${pkgs.gnused}";
      awww = "${inputs.awww.packages.${pkgs.system}.awww}";
      wallpaper_light = "${wallpapers.light}";
      wallpaper_dark = "${wallpapers.dark}";
    };
    executable = true;
  };

  # Monitor hotplug handler script
  home.file.".local/share/monitor-hotplug.sh" = {
    source = pkgs.replaceVars ./monitor-hotplug.sh {
      coreutils = "${pkgs.coreutils}";
      gnugrep = "${pkgs.gnugrep}";
      gnused = "${pkgs.gnused}";
      awww = "${inputs.awww.packages.${pkgs.system}.awww}";
      darkman = "${pkgs.darkman}";
      wallpaper_light = "${wallpapers.light}";
      wallpaper_dark = "${wallpapers.dark}";
    };
    executable = true;
  };

  # Light mode wrapper
  home.file.".local/share/light-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      exec ~/.local/share/darkman-switch-mode.sh light
    '';
    executable = true;
  };

  # Dark mode wrapper
  home.file.".local/share/dark-mode.d/stylix.sh" = {
    text = ''
      #!/run/current-system/sw/bin/bash
      exec ~/.local/share/darkman-switch-mode.sh dark
    '';
    executable = true;
  };

  # Systemd service to monitor for display changes and refresh wallpaper
  # Uses udevadm monitor for DRM subsystem events (sysfs files don't generate inotify events)
  systemd.user.services.monitor-hotplug = {
    Unit = {
      Description = "Monitor hotplug wallpaper refresh";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };

    Service = {
      Type = "simple";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.systemd}/bin/udevadm monitor --udev --subsystem-match=drm | while read -r line; do if echo \"$line\" | ${pkgs.gnugrep}/bin/grep -q \"change\"; then sleep 2; ~/.local/share/monitor-hotplug.sh; fi; done'";
      Restart = "always";
      RestartSec = "3";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
