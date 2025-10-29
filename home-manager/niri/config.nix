{
  pkgs,
  ...
}:
{
  home.packages = [
    pkgs.niri
    pkgs.playerctl
    pkgs.wireplumber
    pkgs.xwayland-satellite
    pkgs.brightnessctl
  ];
  services.gnome-keyring.enable = true;

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];
    configPackages = [ pkgs.niri ];
  };

  # https://github.com/YaLTeR/niri/blob/main/resources/default-config.kdl

  xdg.configFile."niri/config.kdl".text = ''
    output "eDP-1" {
        scale 1.25
        background-color "#191033"
    }

    input {
        touchpad {
            tap
            natural-scroll
            dwt
            click-method "clickfinger"
        }
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
            active-color "#61afef"
        }
        border {
            width 3
            active-color "#3e4451"
            inactive-color "#3e4451"
        }
    }

    binds {
        Mod+L { spawn "kitty"; }
        Mod+Q { close-window; }
        Mod+Shift+Ctrl+L { quit skip-confirmation=true; }
        Mod+Space { spawn "vicinae" "toggle"; }

        // Window resizing
        Mod+R { switch-preset-column-width; }
        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }
        Mod+Comma { set-column-width "-10%"; }
        Mod+Period { set-column-width "+10%"; }
        Mod+Shift+Comma { set-window-height "-10%"; }
        Mod+Shift+Period { set-window-height "+10%"; }

        // Navigation
        Mod+Left { focus-column-left; }
        Mod+Right { focus-column-right; }
        Mod+Up { focus-window-up; }
        Mod+Down { focus-window-down; }

        // Moving windows
        Mod+Shift+Left { move-column-left; }
        Mod+Shift+Right { move-column-right; }
        Mod+Shift+Up { move-window-up; }
        Mod+Shift+Down { move-window-down; }

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
  '';
}
