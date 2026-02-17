{
  pkgs,
  lib,
  config,
  ...
}:
let
  # Path to the toggle script
  toggleScript = pkgs.writeShellScript "ironbar-toggle" ''
    exec ${pkgs.python3}/bin/python3 ${./toggle-ironbar.py}
  '';

  # Get Stylix colors from the current theme
  inherit (config.lib.stylix) colors;

  # Generate CSS with color variables prepended
  styleWithColors = ''
    /* Stylix color variables (auto-generated from current theme) */
    @define-color base00 #${colors.base00};
    @define-color base01 #${colors.base01};
    @define-color base02 #${colors.base02};
    @define-color base03 #${colors.base03};
    @define-color base04 #${colors.base04};
    @define-color base05 #${colors.base05};
    @define-color base06 #${colors.base06};
    @define-color base07 #${colors.base07};
    @define-color base08 #${colors.base08};
    @define-color base09 #${colors.base09};
    @define-color base0A #${colors.base0A};
    @define-color base0B #${colors.base0B};
    @define-color base0C #${colors.base0C};
    @define-color base0D #${colors.base0D};
    @define-color base0E #${colors.base0E};
    @define-color base0F #${colors.base0F};

    ${builtins.readFile ./style.css}
  '';

  # Battery watching script with injected dependencies
  # Uses upower --monitor-detail for event-driven updates instead of polling
  batteryWatch = pkgs.writeShellScript "battery-watch" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.upower
        pkgs.gawk
        pkgs.gnugrep
        pkgs.coreutils
      ]
    }"
    ${builtins.readFile ./modules/battery/battery-watch.sh}
  '';

  # Happy status script with injected Stylix color
  happyStatus = pkgs.writeShellScript "happy-status" ''
    export ACTIVE_COLOR="${colors.base0B}"
    ${builtins.readFile ./modules/happy/happy-status.sh}
  '';

  # Notification count watching script with injected dependencies
  # Uses dbus-monitor to watch for notification events
  notificationCountWatch = pkgs.writeShellScript "notification-count-watch" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.dunst
        pkgs.dbus
        pkgs.gawk
        pkgs.gnugrep
        pkgs.coreutils
      ]
    }"
    ${builtins.readFile ./modules/notifications/notification-count-watch.sh}
  '';
in
{
  # Install ironbar from nixpkgs (includes all features by default)
  # Note: We do NOT use ironbar's built-in volume module due to a critical crash bug
  # (https://github.com/JakeStanger/ironbar/issues/875). Instead, we use a custom
  # volume script that queries WirePlumber via wpctl.
  home.packages = [
    pkgs.ironbar
    pkgs.jq # For parsing dunst notification history JSON
    pkgs.wireplumber # For wpctl command used by custom volume module (avoids PulseAudio crash)
  ];

  # Create config directory and files
  xdg.configFile = {
    "ironbar/config.json".source = ./config.json;
    "ironbar/style.css".text = styleWithColors;

    # Custom module scripts
    "ironbar/modules/wifi/wifi-status.sh" = {
      source = ./modules/wifi/wifi-status.sh;
      executable = true;
    };
    "ironbar/modules/battery/battery-status.sh" = {
      source = ./modules/battery/battery-status.sh;
      executable = true;
    };
    "ironbar/modules/battery/battery-details.sh" = {
      source = ./modules/battery/battery-details.sh;
      executable = true;
    };
    "ironbar/modules/battery/get-profile.sh" = {
      source = ./modules/battery/get-profile.sh;
      executable = true;
    };
    "ironbar/modules/battery/set-profile.sh" = {
      source = ./modules/battery/set-profile.sh;
      executable = true;
    };
    # Event-driven battery watcher (replaces polling in bar status)
    "ironbar/modules/battery/battery-watch.sh" = {
      source = batteryWatch;
      executable = true;
    };
    "ironbar/modules/notifications/notification-count.sh" = {
      source = ./modules/notifications/notification-count.sh;
      executable = true;
    };
    "ironbar/modules/notifications/notification-history.sh" = {
      source = ./modules/notifications/notification-history.sh;
      executable = true;
    };
    # Event-driven notification watcher (replaces polling in bar status)
    "ironbar/modules/notifications/notification-count-watch.sh" = {
      source = notificationCountWatch;
      executable = true;
    };

    # Custom volume module (replacement for built-in volume module)
    # Uses wpctl to query WirePlumber instead of PulseAudio bindings
    # See modules/volume/README.md for full documentation
    "ironbar/modules/volume/volume-status.sh" = {
      source = ./modules/volume/volume-status.sh;
      executable = true;
    };

    # Tray visibility check
    # Hides tray module when no StatusNotifierItems are registered
    "ironbar/modules/tray/has-tray-items.sh" = {
      source = ./modules/tray/has-tray-items.sh;
      executable = true;
    };

    # Peripheral battery module
    # Shows battery status for connected peripherals (mouse, keyboard)
    "ironbar/modules/peripheral-battery/peripheral-battery-status.sh" = {
      source = ./modules/peripheral-battery/peripheral-battery-status.sh;
      executable = true;
    };
    "ironbar/modules/peripheral-battery/has-peripherals-connected.sh" = {
      source = ./modules/peripheral-battery/has-peripherals-connected.sh;
      executable = true;
    };

    # Aurora module
    # Shows aurora/northern lights activity from NOAA space weather data
    # Hidden when Kp < 4 via show_if in config.json
    "ironbar/modules/aurora/has-aurora-activity.sh" = {
      source = ./modules/aurora/has-aurora-activity.sh;
      executable = true;
    };
    "ironbar/modules/aurora/aurora-status.sh" = {
      source = ./modules/aurora/aurora-status.sh;
      executable = true;
    };
    "ironbar/modules/aurora/aurora-details.sh" = {
      source = ./modules/aurora/aurora-details.sh;
      executable = true;
    };

    # Weather module
    # Shows current weather and forecast from wttr.in
    # Hidden when offline/no data via show_if in config.json
    "ironbar/modules/weather/has-weather-data.sh" = {
      source = ./modules/weather/has-weather-data.sh;
      executable = true;
    };
    "ironbar/modules/weather/weather-status.sh" = {
      source = ./modules/weather/weather-status.sh;
      executable = true;
    };
    "ironbar/modules/weather/weather-forecast.sh" = {
      source = ./modules/weather/weather-forecast.sh;
      executable = true;
    };

    # Removable storage module
    # Shows mounted devices with name+capacity and separate eject buttons
    "ironbar/modules/storage/has-mounted-devices.sh" = {
      source = ./modules/storage/has-mounted-devices.sh;
      executable = true;
    };
    "ironbar/modules/storage/storage-status.sh" = {
      source = ./modules/storage/storage-status.sh;
      executable = true;
    };
    "ironbar/modules/storage/device-name.sh" = {
      source = ./modules/storage/device-name.sh;
      executable = true;
    };
    "ironbar/modules/storage/device-eject.sh" = {
      source = ./modules/storage/device-eject.sh;
      executable = true;
    };
    "ironbar/modules/storage/open-device.sh" = {
      source = ./modules/storage/open-device.sh;
      executable = true;
    };
    "ironbar/modules/storage/eject-device.sh" = {
      source = ./modules/storage/eject-device.sh;
      executable = true;
    };

    # Display module
    # Shows display brightness, ABM controls, and idle inhibition status
    "ironbar/modules/display/display-status.sh" = {
      source = ./modules/display/display-status.sh;
      executable = true;
    };
    "ironbar/modules/display/display-details.sh" = {
      source = ./modules/display/display-details.sh;
      executable = true;
    };
    "ironbar/modules/display/get-auto-status.sh" = {
      source = ./modules/display/get-auto-status.sh;
      executable = true;
    };
    "ironbar/modules/display/toggle-auto.sh" = {
      source = ./modules/display/toggle-auto.sh;
      executable = true;
    };
    "ironbar/modules/display/toggle-stay-on.sh" = {
      source = ./modules/display/toggle-stay-on.sh;
      executable = true;
    };
    "ironbar/modules/display/get-stay-on-status.sh" = {
      source = ./modules/display/get-stay-on-status.sh;
      executable = true;
    };
    "ironbar/modules/display/toggle-redlight.sh" = {
      source = ./modules/display/toggle-redlight.sh;
      executable = true;
    };
    "ironbar/modules/display/get-redlight-status.sh" = {
      source = ./modules/display/get-redlight-status.sh;
      executable = true;
    };

    # Happy module
    # Toggle for Happy remote development daemon
    "ironbar/modules/happy/happy-status.sh" = {
      source = happyStatus;
      executable = true;
    };
    "ironbar/modules/happy/toggle-happy.sh" = {
      source = ./modules/happy/toggle-happy.sh;
      executable = true;
    };

    # Firewall module
    # Shows count of refused connections and per-port breakdown in popup
    # Hidden when no refused connections via show_if
    "ironbar/modules/firewall/has-refused.sh" = {
      source = ./modules/firewall/has-refused.sh;
      executable = true;
    };
    "ironbar/modules/firewall/firewall-status.sh" = {
      source = ./modules/firewall/firewall-status.sh;
      executable = true;
    };
    "ironbar/modules/firewall/firewall-details.sh" = {
      source = ./modules/firewall/firewall-details.sh;
      executable = true;
    };
  };

  # Systemd service for ironbar with niri overview-only mode
  # Note: This replaces the default ironbar.service since we manage ironbar startup ourselves
  systemd.user.services.ironbar = {
    Unit = {
      Description = "Ironbar with niri overview-only mode";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      Type = "simple";
      # Kill any stale ironbar processes before starting (can happen after rebuild)
      # The "-" prefix tells systemd to ignore the exit code (pkill returns 1 if no process found)
      # Use -f to match full command line (Nix wrappers have names like .ironbar-wrappe)
      ExecStartPre = "-${pkgs.procps}/bin/pkill -f ironbar";
      ExecStart = "${toggleScript}";
      Restart = "on-failure";
      RestartSec = "5s";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
