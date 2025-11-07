{
  pkgs,
  osConfig,
  lib,
  ...
}:
let
  # Reference colors from Stylix - the single source of truth
  # Stylix processes the base16 scheme and provides colors
  colors = osConfig.lib.stylix.colors;
in
{
  home.packages = [
    pkgs.niri
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

  xdg.configFile."niri/config.kdl".text = ''
    output "eDP-1" {
        scale 1.25
        background-color "#${colors.base02}"
    }

    output "DP-3" {
        scale 1.25
        variable-refresh-rate on-demand=true
        background-color "#${colors.base02}"
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
        backdrop-color "#${colors.base02}"
        zoom 0.5
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
            active-color "#${colors.base0D}"
        }
        border {
            width 3
            active-color "#${colors.base03}"
            inactive-color "#${colors.base03}"
        }
        insert-hint { color "#${colors.base0D}"; }

        default-column-width { proportion ${toString osConfig.defaults.display.defaultColumnWidthPercent}; }
        preset-column-widths {
            ${lib.concatMapStringsSep "\n            " (
              width: "proportion ${toString width}"
            ) osConfig.defaults.display.columnWidthPercentPresets}
        }
    }

    xwayland-satellite {
        path "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
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
        opacity 0.99
    }

    layer-rule {
        match namespace="notifications"
        block-out-from "screen-capture"
    }

    binds {
        Mod+Shift+Slash { show-hotkey-overlay; }

        Mod+G { spawn "ghostty"; }
        Mod+Q { close-window; }
        Mod+O repeat=false { toggle-overview; }
        Mod+Shift+Ctrl+Q { quit skip-confirmation=true; }
        Mod+Space { spawn "vicinae" "toggle"; }
        Mod+A { spawn "pavucontrol"; }

        Super+Alt+L hotkey-overlay-title="Lock the Screen: swaylock" { spawn "swaylock"; }

        // Navigation
        Mod+Left  { focus-column-left; }
        Mod+Down  { focus-window-down; }
        Mod+Up    { focus-window-up; }
        Mod+Right { focus-column-right; }
        Mod+H     { focus-column-left; }
        Mod+J     { focus-window-down; }
        Mod+K     { focus-window-up; }
        Mod+L     { focus-column-right; }

        Mod+Ctrl+Left  { move-column-left; }
        Mod+Ctrl+Down  { move-window-down; }
        Mod+Ctrl+Up    { move-window-up; }
        Mod+Ctrl+Right { move-column-right; }
        Mod+Ctrl+H     { move-column-left; }
        Mod+Ctrl+J     { move-window-down; }
        Mod+Ctrl+K     { move-window-up; }
        Mod+Ctrl+L     { move-column-right; }

        Mod+Home { focus-column-first; }
        Mod+End  { focus-column-last; }
        Mod+Ctrl+Home { move-column-to-first; }
        Mod+Ctrl+End  { move-column-to-last; }

        Mod+Shift+Left  { focus-monitor-left; }
        Mod+Shift+Down  { focus-monitor-down; }
        Mod+Shift+Up    { focus-monitor-up; }
        Mod+Shift+Right { focus-monitor-right; }
        Mod+Shift+H     { focus-monitor-left; }
        Mod+Shift+J     { focus-monitor-down; }
        Mod+Shift+K     { focus-monitor-up; }
        Mod+Shift+L     { focus-monitor-right; }

        Mod+Shift+Ctrl+Left  { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+Down  { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+Up    { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
        Mod+Shift+Ctrl+H     { move-column-to-monitor-left; }
        Mod+Shift+Ctrl+J     { move-column-to-monitor-down; }
        Mod+Shift+Ctrl+K     { move-column-to-monitor-up; }
        Mod+Shift+Ctrl+L     { move-column-to-monitor-right; }

        Mod+Page_Down      { focus-workspace-down; }
        Mod+Page_Up        { focus-workspace-up; }
        Mod+U              { focus-workspace-down; }
        Mod+I              { focus-workspace-up; }
        Mod+Ctrl+Page_Down { move-column-to-workspace-down; }
        Mod+Ctrl+Page_Up   { move-column-to-workspace-up; }
        Mod+Ctrl+U         { move-column-to-workspace-down; }
        Mod+Ctrl+I         { move-column-to-workspace-up; }

        Mod+Shift+Page_Down { move-workspace-down; }
        Mod+Shift+Page_Up   { move-workspace-up; }
        Mod+Shift+U         { move-workspace-down; }
        Mod+Shift+I         { move-workspace-up; }

        Mod+WheelScrollDown      cooldown-ms=150 { focus-workspace-down; }
        Mod+WheelScrollUp        cooldown-ms=150 { focus-workspace-up; }
        Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
        Mod+Ctrl+WheelScrollUp   cooldown-ms=150 { move-column-to-workspace-up; }

        Mod+WheelScrollRight      { focus-column-right; }
        Mod+WheelScrollLeft       { focus-column-left; }
        Mod+Ctrl+WheelScrollRight { move-column-right; }
        Mod+Ctrl+WheelScrollLeft  { move-column-left; }

        Mod+Shift+WheelScrollDown      { focus-column-right; }
        Mod+Shift+WheelScrollUp        { focus-column-left; }
        Mod+Ctrl+Shift+WheelScrollDown { move-column-right; }
        Mod+Ctrl+Shift+WheelScrollUp   { move-column-left; }

        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        Mod+6 { focus-workspace 6; }
        Mod+7 { focus-workspace 7; }
        Mod+8 { focus-workspace 8; }
        Mod+9 { focus-workspace 9; }
        Mod+Ctrl+1 { move-column-to-workspace 1; }
        Mod+Ctrl+2 { move-column-to-workspace 2; }
        Mod+Ctrl+3 { move-column-to-workspace 3; }
        Mod+Ctrl+4 { move-column-to-workspace 4; }
        Mod+Ctrl+5 { move-column-to-workspace 5; }
        Mod+Ctrl+6 { move-column-to-workspace 6; }
        Mod+Ctrl+7 { move-column-to-workspace 7; }
        Mod+Ctrl+8 { move-column-to-workspace 8; }
        Mod+Ctrl+9 { move-column-to-workspace 9; }

        // Switches focus between the current and the previous workspace.
        Mod+Tab { focus-workspace-previous; }

        Mod+BracketLeft  { consume-or-expel-window-left; }
        Mod+BracketRight { consume-or-expel-window-right; }

        // Consume one window from the right to the bottom of the focused column.
        Mod+Comma  { consume-window-into-column; }
        // Expel the bottom window from the focused column to the right.
        Mod+Period { expel-window-from-column; }

        Mod+R { switch-preset-column-width; }
        // Cycling through the presets in reverse order is also possible.
        // Mod+R { switch-preset-column-width-back; }
        Mod+Shift+R { switch-preset-window-height; }
        Mod+Ctrl+R { reset-window-height; }
        Mod+F { maximize-column; }
        Mod+Shift+F { fullscreen-window; }

        // Expand the focused column to space not taken up by other fully visible columns.
        // Makes the column "fill the rest of the space".
        Mod+Ctrl+F { expand-column-to-available-width; }

        Mod+C { center-column; }

        // Center all fully visible columns on screen.
        Mod+Ctrl+C { center-visible-columns; }

        Mod+Minus { set-column-width "-10%"; }
        Mod+Equal { set-column-width "+10%"; }

        Mod+Shift+Minus { set-window-height "-10%"; }
        Mod+Shift+Equal { set-window-height "+10%"; }

        // Move the focused window between the floating and the tiling layout.
        Mod+V       { toggle-window-floating; }
        Mod+Shift+V { switch-focus-between-floating-and-tiling; }

        // Toggle tabbed column display mode.
        // Windows in this column will appear as vertical tabs,
        // rather than stacked on top of each other.
        Mod+W { toggle-column-tabbed-display; }

        Print { screenshot; }
        Ctrl+Print { screenshot-screen; }
        Alt+Print { screenshot-window; }

        // The quit action will show a confirmation dialog to avoid accidental exits.
        Mod+Shift+E { quit; }
        Ctrl+Alt+Delete { quit; }

        // Powers off the monitors. To turn them back on, do any input like
        // moving the mouse or pressing any other key.
        Mod+Shift+P { power-off-monitors; }

        // XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
        // XF86AudioMute { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
        // XF86AudioNext { spawn "playerctl" "next"; }
        // XF86AudioPlay { spawn "playerctl" "play-pause"; }
        // XF86AudioPrev { spawn "playerctl" "previous"; }
        // XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
        // XF86AudioStop { spawn "playerctl" "stop"; }
        // XF86MonBrightnessDown { spawn "brightnessctl" "set" "5%-"; }
        // XF86MonBrightnessUp { spawn "brightnessctl" "set" "5%+"; }
    }
  '';
}
