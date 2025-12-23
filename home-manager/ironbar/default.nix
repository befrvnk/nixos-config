{
  pkgs,
  config,
  ...
}:
let
  # Path to the toggle script
  toggleScript = pkgs.writeShellScript "ironbar-toggle" ''
    exec ${pkgs.python3}/bin/python3 ${./toggle-ironbar.py}
  '';

  # Get Stylix colors from the current theme
  colors = config.lib.stylix.colors;

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
  xdg.configFile."ironbar/config.json".source = ./config.json;
  xdg.configFile."ironbar/style.css".text = styleWithColors;

  # Custom module scripts
  xdg.configFile."ironbar/modules/wifi/wifi-status.sh" = {
    source = ./modules/wifi/wifi-status.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/battery/battery-status.sh" = {
    source = ./modules/battery/battery-status.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/battery/battery-details.sh" = {
    source = ./modules/battery/battery-details.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/battery/get-profile.sh" = {
    source = ./modules/battery/get-profile.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/battery/set-profile.sh" = {
    source = ./modules/battery/set-profile.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/notifications/notification-count.sh" = {
    source = ./modules/notifications/notification-count.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/notifications/notification-history.sh" = {
    source = ./modules/notifications/notification-history.sh;
    executable = true;
  };

  # Custom volume module (replacement for built-in volume module)
  # Uses wpctl to query WirePlumber instead of PulseAudio bindings
  # See modules/volume/README.md for full documentation
  xdg.configFile."ironbar/modules/volume/volume-status.sh" = {
    source = ./modules/volume/volume-status.sh;
    executable = true;
  };

  # CPU governor status module
  # Shows current CPU governor (powersave or schedutil)
  xdg.configFile."ironbar/modules/cpu-governor/cpu-governor-status.sh" = {
    source = ./modules/cpu-governor/cpu-governor-status.sh;
    executable = true;
  };

  # CPU governor visibility check
  # Only shows module when governor is powersave
  xdg.configFile."ironbar/modules/cpu-governor/is-powersave.sh" = {
    source = ./modules/cpu-governor/is-powersave.sh;
    executable = true;
  };

  # Tray visibility check
  # Hides tray module when no StatusNotifierItems are registered
  xdg.configFile."ironbar/modules/tray/has-tray-items.sh" = {
    source = ./modules/tray/has-tray-items.sh;
    executable = true;
  };

  # Logitech mouse battery module
  # Shows battery status for mice connected via Logitech USB receivers
  xdg.configFile."ironbar/modules/mouse-battery/mouse-battery-status.sh" = {
    source = ./modules/mouse-battery/mouse-battery-status.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/mouse-battery/has-mouse-connected.sh" = {
    source = ./modules/mouse-battery/has-mouse-connected.sh;
    executable = true;
  };

  # Removable storage module
  # Shows mounted devices with name+capacity and separate eject buttons
  xdg.configFile."ironbar/modules/storage/has-mounted-devices.sh" = {
    source = ./modules/storage/has-mounted-devices.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/storage/storage-status.sh" = {
    source = ./modules/storage/storage-status.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/storage/device-name.sh" = {
    source = ./modules/storage/device-name.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/storage/device-eject.sh" = {
    source = ./modules/storage/device-eject.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/storage/open-device.sh" = {
    source = ./modules/storage/open-device.sh;
    executable = true;
  };
  xdg.configFile."ironbar/modules/storage/eject-device.sh" = {
    source = ./modules/storage/eject-device.sh;
    executable = true;
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
