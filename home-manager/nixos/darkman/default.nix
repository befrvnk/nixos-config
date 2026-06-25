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
  home = {
    # Darkman configuration
    file = {
      ".config/darkman/config.yaml".text = ''
        lat: 48.13743
        lng: 11.57549
      '';

      # Darkman scripts for theme switching
      # Note: darkman looks for scripts in XDG_DATA_HOME/light-mode.d and XDG_DATA_HOME/dark-mode.d
      # NOT in a darkman subdirectory!

      # Unified theme switching script
      ".local/share/darkman-switch-mode.sh" = {
        source = pkgs.replaceVars ./darkman-switch-mode.sh {
          dconf = "${pkgs.dconf}";
          systemd = "${pkgs.systemd}";
          niri = "${pkgs.niri}";
          coreutils = "${pkgs.coreutils}";
          gnugrep = "${pkgs.gnugrep}";
          util_linux = "${pkgs.util-linux}";
          gnused = "${pkgs.gnused}";
          awww = "${inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww}";
          wallpaper_light = "${wallpapers.light}";
          wallpaper_dark = "${wallpapers.dark}";
        };
        executable = true;
      };

      # Monitor hotplug handler script
      ".local/share/monitor-hotplug.sh" = {
        source = pkgs.replaceVars ./monitor-hotplug.sh {
          coreutils = "${pkgs.coreutils}";
          gnugrep = "${pkgs.gnugrep}";
          gnused = "${pkgs.gnused}";
          awww = "${inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww}";
          darkman = "${pkgs.darkman}";
          wallpaper_light = "${wallpapers.light}";
          wallpaper_dark = "${wallpapers.dark}";
        };
        executable = true;
      };

      ".local/share/monitor-hotplug-watch.sh" = {
        source = pkgs.replaceVars ./monitor-hotplug-watch.sh {
          coreutils = "${pkgs.coreutils}";
          gnugrep = "${pkgs.gnugrep}";
          systemd = "${pkgs.systemd}";
        };
        executable = true;
      };

      ".local/share/restart-darkman.sh" = {
        source = pkgs.replaceVars ./restart-darkman.sh {
          coreutils = "${pkgs.coreutils}";
          darkman = "${pkgs.darkman}";
          awww = "${inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww}";
        };
        executable = true;
      };

      # Light mode wrapper
      ".local/share/light-mode.d/stylix.sh" = {
        text = ''
          #!/run/current-system/sw/bin/bash
          exec ~/.local/share/darkman-switch-mode.sh light
        '';
        executable = true;
      };

      # Dark mode wrapper
      ".local/share/dark-mode.d/stylix.sh" = {
        text = ''
          #!/run/current-system/sw/bin/bash
          exec ~/.local/share/darkman-switch-mode.sh dark
        '';
        executable = true;
      };
    };

    # Re-apply the current darkman mode after Home Manager activation.
    # Run late so the normal generation has finished linking before the Stylix
    # specialisation activation touches the same files.
    activation.restartDarkman =
      config.lib.dag.entryAfter
        [
          "reloadSystemd"
          "stylixLookAndFeel"
          "zedSettingsActivation"
        ]
        ''
          DARKMAN_FROM_HOME_MANAGER=1 $DRY_RUN_CMD "$HOME/.local/share/restart-darkman.sh"
        '';
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
      ExecStart = "%h/.local/share/monitor-hotplug-watch.sh";
      Restart = "always";
      RestartSec = "3";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
