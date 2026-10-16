{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  wallpapers = import ../wallpapers;
  fonts = config.stylix.fonts;
  noctalia = config.programs.noctalia.package;
  awww = inputs.awww.packages.${pkgs.stdenv.hostPlatform.system}.awww;
  request = pkgs.writeShellScript "noctalia-theme-request" ''
    exec ${pkgs.python3}/bin/python3 ${./theme_bridge.py} request "$@"
  '';
  worker = pkgs.writeShellScript "noctalia-theme-worker" ''
    exec ${pkgs.python3}/bin/python3 ${./theme_bridge.py} run
  '';
  hotplug = pkgs.writeShellScript "noctalia-monitor-hotplug" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.systemd
      ]
    }"
    exec ${pkgs.bash}/bin/bash ${./monitor-hotplug.sh} ${request}
  '';
in
{
  # The GNOME target otherwise writes color-scheme during every HM activation,
  # overwriting Noctalia's runtime preference (light maps to "default"). Keep
  # its app font defaults explicitly; GNOME Shell assets are unused on Niri.
  stylix.targets.gnome.enable = false;
  dconf.settings."org/gnome/desktop/interface" = {
    font-name = "${fonts.sansSerif.name} ${toString fonts.sizes.applications}";
    document-font-name = "${fonts.serif.name} ${toString (fonts.sizes.applications - 1)}";
    monospace-font-name = "${fonts.monospace.name} ${toString fonts.sizes.applications}";
  };

  programs.noctalia.settings = {
    theme = {
      # Noctalia owns runtime mode/scheduling. These fields are deliberately
      # identical in both prebuilt HM specialisations, preventing shell restarts.
      mode = "auto";
      shell_mode = "follow";
      sync_color_scheme = true;
    };
    hooks = {
      started = lib.mkAfter [ "${request} --refresh" ];
      theme_mode_changed = "${request}";
    };
  };

  home.activation = {
    noctaliaThemeLock = lib.hm.dag.entryBefore [ "writeBoundary" ] (
      lib.replaceStrings
        [ "@coreutils@" "@systemd@" "@util_linux@" ]
        [ "${pkgs.coreutils}" "${pkgs.systemd}" "${pkgs.util-linux}" ]
        (builtins.readFile ./activation-lock.sh)
    );
    # Request asynchronously, never run a nested activation while holding the
    # normal activation lock. The bridge's own specialisation skips this hook.
    noctaliaThemeRequest =
      lib.hm.dag.entryAfter [ "reloadSystemd" "stylixLookAndFeel" "zedSettingsActivation" ]
        ''
          if [ -z "''${DRY_RUN_CMD:-}" ] && [ -z "''${NOCTALIA_THEME_BRIDGE_ACTIVE:-}" ]; then
            ${request} --force --refresh
          fi
        '';
  };

  systemd.user = {
    paths.noctalia-theme = {
      Unit = {
        Description = "Apply pending Noctalia app-theme compatibility requests";
        After = [ "graphical-session.target" ];
        PartOf = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };
      Path = {
        PathExists = "%t/noctalia-theme/request.json";
        Unit = "noctalia-theme.service";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    services = {
      noctalia-theme = {
        Unit = {
          Description = "Noctalia to prebuilt Home Manager app-theme compatibility bridge";
          After = [ "noctalia.service" ];
          Requires = [ "noctalia.service" ];
          PartOf = [ "graphical-session.target" ];
          ConditionEnvironment = "WAYLAND_DISPLAY";
          StartLimitIntervalSec = 0;
        };
        Service = {
          Type = "oneshot";
          ExecStart = worker;
          Restart = "on-failure";
          RestartSec = "5s";
          TimeoutStartSec = "infinity";
          Environment = [
            "NOCTALIA_COMMAND=${lib.getExe noctalia}"
            "NOCTALIA_AWWW=${awww}/bin/awww"
            "NOCTALIA_WALLPAPER_LIGHT=${wallpapers.light}"
            "NOCTALIA_WALLPAPER_DARK=${wallpapers.dark}"
            "NOCTALIA_HM_UNIT=home-manager-${config.home.username}.service"
            "PATH=${
              lib.makeBinPath [
                pkgs.nix
                pkgs.systemd
              ]
            }:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
          ];
        };
      };

      # Keep the existing wallpaper backend while removing all Darkman queries.
      monitor-hotplug = {
        Unit = {
          Description = "Refresh awww from Noctalia mode after monitor hotplug";
          After = [ "graphical-session.target" ];
          PartOf = [ "graphical-session.target" ];
        };
        Service = {
          ExecStart = hotplug;
          Restart = "always";
          RestartSec = "3s";
        };
        Install.WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
