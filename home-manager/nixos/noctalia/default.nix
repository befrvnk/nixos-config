{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  themes = import ../../../shared/themes.nix { };
  palette = colors: {
    mPrimary = colors.base0D;
    mOnPrimary = colors.base00;
    mSecondary = colors.base0C;
    mOnSecondary = colors.base00;
    mTertiary = colors.base0E;
    mOnTertiary = colors.base00;
    mError = colors.base08;
    mOnError = colors.base00;
    mSurface = colors.base00;
    mOnSurface = colors.base05;
    mSurfaceVariant = colors.base01;
    mOnSurfaceVariant = colors.base04;
    mOutline = colors.base03;
    mShadow = colors.base00;
    mHover = colors.base02;
    mOnHover = colors.base05;
  };
  noctalia = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  overviewWatcher = pkgs.writeShellScript "noctalia-overview" ''
    exec ${pkgs.python3}/bin/python3 ${./overview.py} ${lib.getExe noctalia}
  '';
in
{
  imports = [ inputs.noctalia.homeModules.default ];

  # Palettes/font are supplied below; avoid competing automatic Stylix settings.
  stylix.targets.noctalia.enable = false;

  programs.noctalia = {
    enable = true;
    package = noctalia;
    systemd.enable = true;
    checkConfig = true;
    customPalettes.Stylix = {
      dark = palette themes.dark.palette;
      light = palette themes.light.palette;
    };
    settings = {
      shell = {
        font_family = "JetBrainsMono Nerd Font";
        polkit_agent = false;
        clipboard_enabled = false;
        telemetry_enabled = false;
        niri_overview_type_to_launch_enabled = false;
        panel = {
          control_center_placement = "floating";
          open_near_click_control_center = true;
        };
      };
      theme = {
        mode = config.stylix.polarity;
        source = "custom";
        custom_palette = "Stylix";
      };
      bar.main = {
        position = "top";
        thickness = 34;
        background_opacity = 0.0;
        compositor_blur = false;
        shadow = false;
        margin_ends = 16;
        margin_edge = 16;
        padding = 0;
        widget_spacing = 16;
        font_scale = 1.14;
        auto_hide = false;
        smart_auto_hide = false;
        show_on_workspace_switch = false;
        reserve_space = false;
        capsule = true;
        capsule_padding = 12;
        capsule_fill = "surface";
        capsule_border = "outline";
        capsule_border_width = 1.0;
        color = "on_surface";
        start = [
          "cpu"
          "ram"
          "temperature"
        ];
        center = [
          "weather"
          "clock"
        ];
        end = [
          "tray"
          "notifications"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "battery"
          "control-center"
        ];
      };
      widget = {
        cpu = {
          type = "sysmon";
          stat = "cpu_usage";
          visualization = "none";
          highlight_color = "on_surface";
        };
        ram = {
          type = "sysmon";
          stat = "ram_pct";
          visualization = "none";
          highlight_color = "on_surface";
        };
        temperature = {
          type = "sysmon";
          stat = "cpu_temp";
          visualization = "none";
          highlight_color = "on_surface";
        };
        clock = {
          format = "{:%a %d %b  %H:%M}";
          anchor = true;
        };
        network.show_label = true;
        bluetooth = {
          show_label = true;
          hide_when_adapter_off = false;
        };
        battery.warning_color = "on_surface";
      };
      location = {
        latitude = 48.1521;
        longitude = 11.6584;
        auto_locate = false;
      };
      notification = {
        enable_daemon = true;
        position = "top_center";
      };
      battery.warning_threshold = 0; # Existing battery-notifications owns alerts.
      # Keep the existing managers; do not start competing surfaces/services.
      wallpaper.enabled = false;
      backdrop.enabled = false;
      dock.enabled = false;
      desktop_widgets.enabled = false;
      lockscreen.enabled = false;
      idle.behavior = {
        lock.enabled = false;
        screen-off.enabled = false;
      };
      nightlight.enabled = false;
      osd.kinds = {
        volume = false;
        brightness = false;
        lock_keys = false;
      };
      plugins.auto_update = "none";
      # The hook runs after IPC becomes ready, including on shell restart.
      hooks.started = "${pkgs.systemd}/bin/systemctl --user --no-block restart noctalia-overview.service";
    };
  };

  systemd.user.services.noctalia.Unit.ConditionEnvironment = "WAYLAND_DISPLAY";
  systemd.user.services.noctalia-overview = {
    Unit = {
      Description = "Show Noctalia only in Niri overview";
      After = [ "noctalia.service" ];
      PartOf = [ "noctalia.service" ];
      ConditionEnvironment = [
        "WAYLAND_DISPLAY"
        "NIRI_SOCKET"
      ];
    };
    Service = {
      ExecStart = overviewWatcher;
      Restart = "on-failure";
      RestartSec = "2s";
    };
  };

  programs.niri.settings.window-rules = [
    {
      matches = [ { app-id = "^dev\\.noctalia\\.Noctalia$"; } ];
      open-floating = true;
      default-column-width.fixed = 1080;
      default-window-height.fixed = 920;
    }
  ];
}
