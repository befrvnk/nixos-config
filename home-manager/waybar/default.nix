{
  pkgs,
  osConfig,
  ...
}:
let
  # Use color palette from Stylix
  colors = osConfig.lib.stylix.colors;

  # Read base CSS file
  baseStyle = builtins.readFile ./style.css;

  # Generate CSS with color variables replaced
  styleWithColors =
    builtins.replaceStrings
      [
        "@base00"
        "@base01"
        "@base02"
        "@base03"
        "@base04"
        "@base05"
        "@base06"
        "@base07"
        "@base08"
        "@base09"
        "@base0A"
        "@base0B"
        "@base0C"
        "@base0D"
        "@base0E"
        "@base0F"
      ]
      [
        "#${colors.base00}"
        "#${colors.base01}"
        "#${colors.base02}"
        "#${colors.base03}"
        "#${colors.base04}"
        "#${colors.base05}"
        "#${colors.base06}"
        "#${colors.base07}"
        "#${colors.base08}"
        "#${colors.base09}"
        "#${colors.base0A}"
        "#${colors.base0B}"
        "#${colors.base0C}"
        "#${colors.base0D}"
        "#${colors.base0E}"
        "#${colors.base0F}"
      ]
      baseStyle;

  # Path to the toggle script
  toggleScript = pkgs.writeShellScript "waybar-toggle" ''
    exec ${pkgs.python3}/bin/python3 ${./toggle-waybar.py}
  '';

  # Notification count script that outputs JSON
  notificationScript = pkgs.writeShellScript "dunst-count" ''
    count=$(${pkgs.dunst}/bin/dunstctl count | grep "Waiting" | awk '{print $2}')
    echo "{\"text\":\"$count\",\"tooltip\":\"$count notification(s)\"}"
  '';
in
{
  # Enable waybar
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        # Bar configuration
        layer = "top";
        position = "top";
        exclusive = false;
        height = 60;
        spacing = 8;

        # Start hidden, use explicit show/hide signals
        start_hidden = true;
        on-sigusr1 = "show";
        on-sigusr2 = "hide";

        # Module layout
        modules-left = [
          "niri/workspaces"
          "niri/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "cpu"
          "memory"
          "custom/notifications"
          "battery"
          "network"
          "bluetooth"
          "pulseaudio"
        ];

        # Niri workspaces module
        "niri/workspaces" = {
          all-outputs = false;
        };

        # Niri window module - shows window list with icons
        "niri/window" = {
          format = "{title}";
          icon = true;
          icon-size = 20;
          max-length = 50;
          rewrite = {
            "(.*) - Mozilla Firefox" = "  $1";
            "(.*) - Chromium" = "  $1";
            "(.*)" = "$1";
          };
        };

        # Clock module
        clock = {
          format = "{:%H:%M}";
          format-alt = "{:%Y-%m-%d %H:%M:%S}";
          tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
          interval = 1;
        };

        # CPU module
        cpu = {
          format = "  {usage}%";
          tooltip = true;
          interval = 2;
        };

        # Memory module
        memory = {
          format = "  {percentage}%";
          tooltip-format = "RAM: {used:0.1f}G / {total:0.1f}G\nSwap: {swapUsed:0.1f}G / {swapTotal:0.1f}G";
          interval = 2;
        };

        # Custom notifications module
        "custom/notifications" = {
          exec = "${notificationScript}";
          return-type = "json";
          format = "  {}";
          on-click = "${pkgs.dunst}/bin/dunstctl history-pop";
          interval = 1;
        };

        # Network module
        network = {
          format-wifi = "  {essid} ({signalStrength}%)";
          format-ethernet = "  {ifname}";
          format-disconnected = "  Disconnected";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ifname}: {ipaddr}/{cidr}";
          max-length = 50;
        };

        # Bluetooth module
        bluetooth = {
          format = " {status}";
          format-connected = " {device_alias}";
          format-connected-battery = " {device_alias} {device_battery_percentage}%";
          tooltip-format = "{controller_alias}\t{controller_address}\n\n{num_connections} connected";
          tooltip-format-connected = "{controller_alias}\t{controller_address}\n\n{num_connections} connected\n\n{device_enumerate}";
          tooltip-format-enumerate-connected = "{device_alias}\t{device_address}";
          tooltip-format-enumerate-connected-battery = "{device_alias}\t{device_address}\t{device_battery_percentage}%";
          on-click = "${pkgs.blueman}/bin/blueman-manager";
        };

        # Battery module
        battery = {
          states = {
            warning = 30;
            critical = 15;
          };
          format = "{icon} {capacity}%";
          format-charging = " {capacity}%";
          format-plugged = " {capacity}%";
          format-icons = [
            ""
            ""
            ""
            ""
            ""
          ];
          tooltip-format = "{timeTo}, {capacity}%";
        };

        # Pulseaudio/Volume module
        pulseaudio = {
          format = "{icon} {volume}%";
          format-muted = " {volume}%";
          format-icons = {
            default = [
              ""
              ""
              ""
            ];
          };
          on-click = "${pkgs.pavucontrol}/bin/pavucontrol";
          tooltip-format = "{desc}\nVolume: {volume}%";
        };
      };
    };
    style = styleWithColors;
  };

  # Systemd service for waybar toggle script
  # Note: This replaces the default waybar.service since we manage waybar startup ourselves
  systemd.user.services.waybar = {
    Unit = {
      Description = "Waybar with niri overview-only mode";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
      ConditionEnvironment = "WAYLAND_DISPLAY";
    };

    Service = {
      Type = "simple";
      ExecStart = "${toggleScript}";
      Restart = "on-failure";
      RestartSec = "5s";
    };

    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
