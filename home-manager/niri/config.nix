{
  pkgs,
  osConfig,
  nix-colors,
  lib,
  ...
}:
{
  home.packages = [
    pkgs.niri
    pkgs.playerctl
    pkgs.wireplumber
    pkgs.xwayland-satellite
    pkgs.brightnessctl
    pkgs.pavucontrol
  ];
  services.gnome-keyring.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
    configPackages = [ pkgs.niri ];
  };

  # https://github.com/YaLTeR/niri/blob/main/resources/default-config.kdl

  xdg.configFile."niri/config.kdl".text =
    let
      toggle-float-script = pkgs.writeShellScript "toggle-float" ''
        window_width=800
        window_height=600
        margin=15

        is_floating=$(niri msg --json windows | jq -r '.[] | select(.is_focused == true) | .is_floating')

        if [ "$is_floating" = "true" ]; then
          niri msg action toggle-window-floating
          niri msg action set-column-width ${
            toString (osConfig.defaults.display.defaultColumnWidthPercent * 100)
          }%
          niri msg action reset-window-height
        else
          focused_output=$(niri msg --json workspaces | jq -r '.[] | select(.is_focused == true) | .output')
          scale=$(niri msg --json outputs | jq -r ".[\"$focused_output\"].logical.scale")
          width=$(niri msg --json outputs | jq -r ".[\"$focused_output\"].logical.width")
          height=$(niri msg --json outputs | jq -r ".[\"$focused_output\"].logical.height")

          x=$((width - window_width - margin))
          y=$((height - window_height - margin))

          niri msg action toggle-window-floating
          niri msg action set-window-width $window_width
          niri msg action set-window-height $window_height
          niri msg action move-floating-window --x $x --y $y
        fi
      '';
    in
    ''
      output "eDP-1" {
          scale 1.25
          background-color "#${osConfig.defaults.colorScheme.palette.base02}"
      }

      output "DP-3" {
          scale 1.25
          variable-refresh-rate on-demand=true
          background-color "#${osConfig.defaults.colorScheme.palette.base02}"
      }

      input {
          touchpad {
              tap
              natural-scroll
              dwt
              click-method "clickfinger"
          }
          mouse {
              natural-scroll
              accel-speed -0.5
          }
          warp-mouse-to-focus
          workspace-auto-back-and-forth
      }

      cursor {
          xcursor-theme "default"
          xcursor-size 24
          hide-when-typing
      }

      prefer-no-csd

      overview {
          backdrop-color "#${osConfig.defaults.colorScheme.palette.base02}"
          zoom 0.75
      }

      layout {
          gaps 12
          background-color "transparent"
          struts {
              left 0
              right 0
              top 0
              bottom 0
          }
          focus-ring {
              width 3
              active-color "#${osConfig.defaults.colorScheme.palette.base0D}"
          }
          border {
              width 3
              active-color "#${osConfig.defaults.colorScheme.palette.base03}"
              inactive-color "#${osConfig.defaults.colorScheme.palette.base03}"
          }
          insert-hint { color "rgb(${nix-colors.lib-core.conversions.hexToRGBString " " osConfig.defaults.colorScheme.palette.base0D} / 50%)"; }

          default-column-width { proportion ${toString osConfig.defaults.display.defaultColumnWidthPercent}; }
          preset-column-widths {
              ${lib.concatMapStringsSep "\n            " (
                width: "proportion ${toString width}"
              ) osConfig.defaults.display.columnWidthPercentPresets}
          }
          center-focused-column "on-overflow"
      }

      xwayland-satellite {
          path "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
      }

      binds {
          Mod+G { spawn "ghostty"; }
          Mod+Q { close-window; }
          Mod+Shift+Ctrl+L { quit skip-confirmation=true; }
          Mod+Space { spawn "vicinae" "toggle"; }
          Mod+A { spawn "pavucontrol"; }

          // Floating
          Mod+Tab { switch-focus-between-floating-and-tiling; }
          Mod+Return { spawn "${toggle-float-script}"; }

          // Window resizing
          Mod+R { switch-preset-column-width; }
          Mod+F { maximize-column; }
          Mod+Shift+F { fullscreen-window; }
          Mod+Comma { set-column-width "-10%"; }
          Mod+Period { set-column-width "+10%"; }
          Mod+Shift+Comma { set-window-height "-10%"; }
          Mod+Shift+Period { set-window-height "+10%"; }

          // Navigation (Arrow keys)
          Mod+Left { focus-column-left; }
          Mod+Right { focus-column-right; }
          Mod+Up { focus-workspace-up; }
          Mod+Down { focus-workspace-down; }

          // Navigation (Vim style)
          Mod+H { focus-column-left; }
          Mod+L { focus-column-right; }
          Mod+K { focus-workspace-up; }
          Mod+J { focus-workspace-down; }

          // Moving windows (Arrow keys)
          Mod+Shift+Left { move-column-left; }
          Mod+Shift+Right { move-column-right; }
          Mod+Shift+Up { move-window-to-workspace-up; }
          Mod+Shift+Down { move-window-to-workspace-down; }

          // Moving windows (Vim style)
          Mod+Shift+H { move-column-left; }
          Mod+Shift+L { move-column-right; }
          Mod+Shift+K { move-window-to-workspace-up; }
          Mod+Shift+J { move-window-to-workspace-down; }

          Mod+C { center-column; }
          Print { screenshot; }
          Shift+Print { screenshot-window; }
          XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
          XF86AudioMute { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
          XF86AudioNext { spawn "playerctl" "next"; }
          XF86AudioPlay { spawn "playerctl" "play-pause"; }
          XF86AudioPrev { spawn "playerctl" "previous"; }
          XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
          XF86AudioStop { spawn "playerctl" "stop"; }
          XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }
          XF86MonBrightnessUp { spawn "brightnessctl" "set" "5%+"; }
      }

      window-rule {
          draw-border-with-background false
          geometry-corner-radius 8.0 8.0 8.0 8.0
          clip-to-geometry true
      }

      window-rule {
          match is-floating=true
          geometry-corner-radius 16.0 16.0 16.0 16.0
      }

      window-rule {
          match is-active=false
          opacity 0.9
      }

      layer-rule {
          match namespace="notifications"
          block-out-from "screen-capture"
      }
    '';
}
