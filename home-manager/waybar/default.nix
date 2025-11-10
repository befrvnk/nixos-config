{
  pkgs,
  lib,
  ...
}:
let
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
        height = 40;
        spacing = 8;

        # Start hidden, use explicit show/hide signals
        start_hidden = true;
        on-sigusr1 = "show";
        on-sigusr2 = "hide";

        # Automatically reload style when CSS file changes
        reload_style_on_change = true;

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
    # Append custom styles on top of Stylix's generated CSS
    # This allows Stylix to handle colors while we keep custom layout/styling
    style = lib.mkAfter (builtins.readFile ./style.css);
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
