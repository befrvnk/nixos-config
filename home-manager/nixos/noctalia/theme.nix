{
  config,
  lib,
  pkgs,
  ...
}:
let
  fonts = config.stylix.fonts;
  noctalia = config.programs.noctalia.package;
  activationLock = "${config.xdg.stateHome}/noctalia/theme-activation.lock";
  request = pkgs.writeShellScript "noctalia-theme-request" ''
    export XDG_STATE_HOME=${lib.escapeShellArg config.xdg.stateHome}
    exec ${pkgs.python3}/bin/python3 ${./theme_bridge.py} request "$@"
  '';
  worker = pkgs.writeShellScript "noctalia-theme-worker" ''
    exec ${pkgs.python3}/bin/python3 ${./theme_bridge.py} run
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
      theme_mode_changed = [ "${request}" ];
    };
  };

  home.activation = {
    noctaliaThemeLock = lib.hm.dag.entryBefore [ "writeBoundary" ] (
      lib.replaceStrings
        [ "@activation_lock@" "@coreutils@" "@systemd@" "@util_linux@" ]
        [ (lib.escapeShellArg activationLock) "${pkgs.coreutils}" "${pkgs.systemd}" "${pkgs.util-linux}" ]
        (builtins.readFile ./activation-lock.sh)
    );
    # Request asynchronously, never run a nested activation while holding the
    # normal activation lock. The bridge's own specialisation skips this hook.
    noctaliaThemeRequest =
      lib.hm.dag.entryAfter [ "reloadSystemd" "stylixLookAndFeel" "zedSettingsActivation" ]
        (
          lib.replaceStrings
            [ "@systemd@" "@theme_request@" ]
            [ "${pkgs.systemd}" (lib.escapeShellArg "${request}") ]
            (builtins.readFile ./activation-request.sh)
        );
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
          # sd-switch must not await a worker that is itself waiting for HM.
          Type = "exec";
          ExecStart = worker;
          Restart = "on-failure";
          RestartSec = "5s";
          Environment = [
            "NOCTALIA_ACTIVATION_LOCK=${activationLock}"
            "NOCTALIA_COMMAND=${lib.getExe noctalia}"
            "NOCTALIA_HM_UNIT=home-manager-${config.home.username}.service"
            "XDG_STATE_HOME=${config.xdg.stateHome}"
            "PATH=${
              lib.makeBinPath [
                pkgs.nix
                pkgs.systemd
              ]
            }:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
          ];
        };
      };

    };
  };
}
