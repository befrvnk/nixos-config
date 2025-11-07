{
  pkgs,
  osConfig,
  ...
}:
let
  # Reference colors from Stylix - the single source of truth
  # Stylix processes the base16 scheme and provides colors
  colors = osConfig.lib.stylix.colors;
in
{
  home.packages = [
    pkgs.playerctl
    pkgs.wireplumber
    pkgs.xwayland-satellite
    pkgs.brightnessctl
    pkgs.pavucontrol
    pkgs.swaylock
  ];
  services.gnome-keyring.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    config = {
      # Use GTK portal for all interfaces on Niri
      niri = {
        default = "gtk";
        "org.freedesktop.impl.portal.Settings" = "gtk";
      };
    };
  };

  # https://github.com/YaLTeR/niri/blob/main/resources/default-config.kdl
  programs.niri = {
    enable = true;

    # Migrating configuration from KDL to Nix syntax incrementally
    settings = {
      outputs = {
        "eDP-1" = {
          scale = 1.25;
          background-color = "#${colors.base02}";
        };
        "DP-3" = {
          scale = 1.25;
          variable-refresh-rate = "on-demand";
          background-color = "#${colors.base02}";
        };
      };

      input = {
        touchpad = {
          tap = true;
          natural-scroll = true;
          dwt = true;
          click-method = "clickfinger";
        };
        mouse = {
          natural-scroll = true;
        };
        warp-mouse-to-focus.enable = true;
        workspace-auto-back-and-forth = true;
      };

      cursor = {
        theme = "default";
        size = 24;
        hide-when-typing = true;
      };

      prefer-no-csd = true;

      overview = {
        backdrop-color = "#${colors.base02}";
        zoom = 0.5;
      };

      layout = {
        gaps = 12;
        struts = {
          left = 0;
          right = 0;
          top = 0;
          bottom = 0;
        };
        focus-ring = {
          enable = true;
          width = 3;
          active.color = "#${colors.base0D}";
        };
        border = {
          enable = true;
          width = 3;
          active.color = "#${colors.base03}";
          inactive.color = "#${colors.base03}";
        };
        default-column-width = {
          proportion = osConfig.defaults.display.defaultColumnWidthPercent;
        };
        preset-column-widths = map (width: {
          proportion = width;
        }) osConfig.defaults.display.columnWidthPercentPresets;
      };

      spawn-at-startup = [
        { command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ]; }
      ];

      window-rules = [
        {
          draw-border-with-background = false;
          geometry-corner-radius = {
            top-left = 8.0;
            top-right = 8.0;
            bottom-left = 8.0;
            bottom-right = 8.0;
          };
          clip-to-geometry = true;
        }
        {
          matches = [ { is-floating = true; } ];
          geometry-corner-radius = {
            top-left = 16.0;
            top-right = 16.0;
            bottom-left = 16.0;
            bottom-right = 16.0;
          };
        }
        {
          matches = [ { is-active = false; } ];
          opacity = 0.99;
        }
      ];

      layer-rules = [
        {
          matches = [ { namespace = "notifications"; } ];
          block-out-from = "screen-capture";
        }
      ];

      binds = {
        "Mod+Shift+Slash".action.show-hotkey-overlay = { };

        "Mod+G".action.spawn = [ "ghostty" ];
        "Mod+Q".action.close-window = { };
        "Mod+O" = {
          action.toggle-overview = { };
          repeat = false;
        };
        "Mod+Shift+Ctrl+Q".action.quit = {
          skip-confirmation = true;
        };
        "Mod+Space".action.spawn = [
          "vicinae"
          "toggle"
        ];
        "Mod+A".action.spawn = [ "pavucontrol" ];

        "Super+Alt+L" = {
          action.spawn = [ "swaylock" ];
          allow-when-locked = true;
        };

        # Navigation
        "Mod+Left".action.focus-column-left = { };
        "Mod+Down".action.focus-window-down = { };
        "Mod+Up".action.focus-window-up = { };
        "Mod+Right".action.focus-column-right = { };
        "Mod+H".action.focus-column-left = { };
        "Mod+J".action.focus-window-down = { };
        "Mod+K".action.focus-window-up = { };
        "Mod+L".action.focus-column-right = { };

        "Mod+Ctrl+Left".action.move-column-left = { };
        "Mod+Ctrl+Down".action.move-window-down = { };
        "Mod+Ctrl+Up".action.move-window-up = { };
        "Mod+Ctrl+Right".action.move-column-right = { };
        "Mod+Ctrl+H".action.move-column-left = { };
        "Mod+Ctrl+J".action.move-window-down = { };
        "Mod+Ctrl+K".action.move-window-up = { };
        "Mod+Ctrl+L".action.move-column-right = { };

        "Mod+Home".action.focus-column-first = { };
        "Mod+End".action.focus-column-last = { };
        "Mod+Ctrl+Home".action.move-column-to-first = { };
        "Mod+Ctrl+End".action.move-column-to-last = { };

        "Mod+Shift+Left".action.focus-monitor-left = { };
        "Mod+Shift+Down".action.focus-monitor-down = { };
        "Mod+Shift+Up".action.focus-monitor-up = { };
        "Mod+Shift+Right".action.focus-monitor-right = { };
        "Mod+Shift+H".action.focus-monitor-left = { };
        "Mod+Shift+J".action.focus-monitor-down = { };
        "Mod+Shift+K".action.focus-monitor-up = { };
        "Mod+Shift+L".action.focus-monitor-right = { };

        "Mod+Shift+Ctrl+Left".action.move-column-to-monitor-left = { };
        "Mod+Shift+Ctrl+Down".action.move-column-to-monitor-down = { };
        "Mod+Shift+Ctrl+Up".action.move-column-to-monitor-up = { };
        "Mod+Shift+Ctrl+Right".action.move-column-to-monitor-right = { };
        "Mod+Shift+Ctrl+H".action.move-column-to-monitor-left = { };
        "Mod+Shift+Ctrl+J".action.move-column-to-monitor-down = { };
        "Mod+Shift+Ctrl+K".action.move-column-to-monitor-up = { };
        "Mod+Shift+Ctrl+L".action.move-column-to-monitor-right = { };

        "Mod+Page_Down".action.focus-workspace-down = { };
        "Mod+Page_Up".action.focus-workspace-up = { };
        "Mod+U".action.focus-workspace-down = { };
        "Mod+I".action.focus-workspace-up = { };
        "Mod+Ctrl+Page_Down".action.move-column-to-workspace-down = { };
        "Mod+Ctrl+Page_Up".action.move-column-to-workspace-up = { };
        "Mod+Ctrl+U".action.move-column-to-workspace-down = { };
        "Mod+Ctrl+I".action.move-column-to-workspace-up = { };

        "Mod+Shift+Page_Down".action.move-workspace-down = { };
        "Mod+Shift+Page_Up".action.move-workspace-up = { };
        "Mod+Shift+U".action.move-workspace-down = { };
        "Mod+Shift+I".action.move-workspace-up = { };

        "Mod+WheelScrollDown" = {
          action.focus-workspace-down = { };
          cooldown-ms = 150;
        };
        "Mod+WheelScrollUp" = {
          action.focus-workspace-up = { };
          cooldown-ms = 150;
        };
        "Mod+Ctrl+WheelScrollDown" = {
          action.move-column-to-workspace-down = { };
          cooldown-ms = 150;
        };
        "Mod+Ctrl+WheelScrollUp" = {
          action.move-column-to-workspace-up = { };
          cooldown-ms = 150;
        };

        "Mod+WheelScrollRight".action.focus-column-right = { };
        "Mod+WheelScrollLeft".action.focus-column-left = { };
        "Mod+Ctrl+WheelScrollRight".action.move-column-right = { };
        "Mod+Ctrl+WheelScrollLeft".action.move-column-left = { };

        "Mod+Shift+WheelScrollDown".action.focus-column-right = { };
        "Mod+Shift+WheelScrollUp".action.focus-column-left = { };
        "Mod+Ctrl+Shift+WheelScrollDown".action.move-column-right = { };
        "Mod+Ctrl+Shift+WheelScrollUp".action.move-column-left = { };

        "Mod+1".action.focus-workspace = 1;
        "Mod+2".action.focus-workspace = 2;
        "Mod+3".action.focus-workspace = 3;
        "Mod+4".action.focus-workspace = 4;
        "Mod+5".action.focus-workspace = 5;
        "Mod+6".action.focus-workspace = 6;
        "Mod+7".action.focus-workspace = 7;
        "Mod+8".action.focus-workspace = 8;
        "Mod+9".action.focus-workspace = 9;
        "Mod+Ctrl+1".action.move-column-to-workspace = 1;
        "Mod+Ctrl+2".action.move-column-to-workspace = 2;
        "Mod+Ctrl+3".action.move-column-to-workspace = 3;
        "Mod+Ctrl+4".action.move-column-to-workspace = 4;
        "Mod+Ctrl+5".action.move-column-to-workspace = 5;
        "Mod+Ctrl+6".action.move-column-to-workspace = 6;
        "Mod+Ctrl+7".action.move-column-to-workspace = 7;
        "Mod+Ctrl+8".action.move-column-to-workspace = 8;
        "Mod+Ctrl+9".action.move-column-to-workspace = 9;

        "Mod+Tab".action.focus-workspace-previous = { };

        "Mod+BracketLeft".action.consume-or-expel-window-left = { };
        "Mod+BracketRight".action.consume-or-expel-window-right = { };

        "Mod+Comma".action.consume-window-into-column = { };
        "Mod+Period".action.expel-window-from-column = { };

        "Mod+R".action.switch-preset-column-width = { };
        "Mod+Shift+R".action.switch-preset-window-height = { };
        "Mod+Ctrl+R".action.reset-window-height = { };
        "Mod+F".action.maximize-column = { };
        "Mod+Shift+F".action.fullscreen-window = { };

        "Mod+Ctrl+F".action.expand-column-to-available-width = { };

        "Mod+C".action.center-column = { };

        "Mod+Ctrl+C".action.center-visible-columns = { };

        "Mod+Minus".action.set-column-width = "-10%";
        "Mod+Equal".action.set-column-width = "+10%";

        "Mod+Shift+Minus".action.set-window-height = "-10%";
        "Mod+Shift+Equal".action.set-window-height = "+10%";

        "Mod+V".action.toggle-window-floating = { };
        "Mod+Shift+V".action.switch-focus-between-floating-and-tiling = { };

        "Mod+W".action.toggle-column-tabbed-display = { };

        "Print".action.screenshot = { };
        "Ctrl+Print".action.screenshot-screen = { };
        "Alt+Print".action.screenshot-window = { };

        "Mod+Shift+E".action.quit = { };
        "Ctrl+Alt+Delete".action.quit = { };

        "Mod+Shift+P".action.power-off-monitors = { };

        # Function keys
        "XF86AudioLowerVolume".action.spawn = [
          "wpctl"
          "set-volume"
          "@DEFAULT_AUDIO_SINK@"
          "5%-"
        ];
        "XF86AudioMute".action.spawn = [
          "wpctl"
          "set-mute"
          "@DEFAULT_AUDIO_SINK@"
          "toggle"
        ];
        "XF86AudioNext".action.spawn = [
          "playerctl"
          "next"
        ];
        "XF86AudioPlay".action.spawn = [
          "playerctl"
          "play-pause"
        ];
        "XF86AudioPrev".action.spawn = [
          "playerctl"
          "previous"
        ];
        "XF86AudioRaiseVolume".action.spawn = [
          "wpctl"
          "set-volume"
          "@DEFAULT_AUDIO_SINK@"
          "5%+"
        ];
        "XF86AudioStop".action.spawn = [
          "playerctl"
          "stop"
        ];
        "XF86MonBrightnessDown".action.spawn = [
          "brightnessctl"
          "set"
          "5%-"
        ];
        "XF86MonBrightnessUp".action.spawn = [
          "brightnessctl"
          "set"
          "5%+"
        ];
      };
    };
  };

}
