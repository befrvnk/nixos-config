{
  pkgs,
  ...
}:
let

  # Path to the toggle script
  toggleScript = pkgs.writeShellScript "waybar-toggle" ''
    exec ${pkgs.python3}/bin/python3 ${./toggle-waybar.py}
  '';
in
{
  # Enable waybar
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        # Bar configuration
        layer = "overlay";
        position = "top";
        exclusive = false;
        height = 40;
        spacing = 8;

        # Module layout
        modules-left = [
          "niri/workspaces"
          "niri/window"
        ];
        modules-center = [ "clock" ];
        modules-right = [
          "cpu"
          "memory"
          "network"
          "battery"
        ];

        # Niri workspaces module
        "niri/workspaces" = {
          format = "{icon}";
          format-icons = {
            default = "○";
            active = "●";
            focused = "◉";
          };
          all-outputs = false;
        };

        # Niri window module
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

        # Network module
        network = {
          format-wifi = "  {essid} ({signalStrength}%)";
          format-ethernet = "  {ifname}";
          format-disconnected = "  Disconnected";
          tooltip-format = "{ifname}: {ipaddr}/{cidr}";
          tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ifname}: {ipaddr}/{cidr}";
          max-length = 50;
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
      };
    };
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
