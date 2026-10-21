{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  noctalia = inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default;
  overviewWatcher = pkgs.writeShellScript "noctalia-overview" ''
    exec ${pkgs.python3}/bin/python3 ${./overview.py} ${lib.getExe noctalia}
  '';
in
{
  imports = [
    inputs.noctalia.homeModules.default
    ./btop.nix
    ./emacs.nix
    ./fzf.nix
    ./ghostty.nix
    ./gtk.nix
    ./lazygit.nix
    ./niri.nix
    ./nushell.nix
    ./osd.nix
    ./plugins.nix
    ./qt.nix
    ./starship.nix
    ./storage.nix
    ./theme.nix
    ./vicinae.nix
    ./vscode.nix
    ./wallpaper.nix
    ./zed.nix
    ./zen-browser.nix
  ];

  # Noctalia owns its palette/font; avoid competing automatic Stylix settings.
  stylix.targets.noctalia.enable = false;

  programs.noctalia = {
    enable = true;
    package = noctalia;
    systemd.enable = true;
    checkConfig = true;
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
        source = "builtin";
        builtin = "Catppuccin";
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
          "storage"
          "notifications"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "caffeine"
          "lid-guard"
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
        # Lid Guard is manual-only; loading the plugin does not acquire a lock.
        lid-guard.type = "8bury/lid-guard:lid-guard";
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
      # Noctalia owns battery warnings: low at 20%, native critical at 5%/2%.
      battery.warning_threshold = 20;
      # Keep the existing managers; do not start competing surfaces/services.
      dock.enabled = false;
      desktop_widgets.enabled = false;
      lockscreen.enabled = false;
      idle.behavior = {
        lock.enabled = false;
        screen-off.enabled = false;
      };
      nightlight.enabled = false;
      osd.kinds = {
        lock_keys = false;
      };
      # The hook runs after IPC becomes ready, including on shell restart.
      hooks.started = [
        "${pkgs.systemd}/bin/systemctl --user --no-block restart noctalia-overview.service"
      ];
    };
  };

  # A rebuild can stop PartOf dependents even when a concurrent start cancels
  # Noctalia's own restart. Its started hook then never runs. Recover the watcher
  # after unit reconciliation too, without restarting either running service.
  home.activation.noctaliaOverviewEnsure = lib.hm.dag.entryAfter [ "reloadSystemd" ] ''
    $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user --no-block start noctalia-overview.service
  '';

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
    Install.WantedBy = [ "graphical-session.target" ];
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
