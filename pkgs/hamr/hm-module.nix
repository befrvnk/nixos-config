{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.hamr;
in
{
  options.programs.hamr = {
    enable = lib.mkEnableOption "hamr launcher for Wayland compositors";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hamr;
      defaultText = lib.literalExpression "pkgs.hamr";
      description = "The hamr package to use.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    # Symlink config to where quickshell expects it
    xdg.configFile."quickshell/hamr".source = "${cfg.package}/share/quickshell/hamr";

    # Systemd user service for hamr daemon
    systemd.user.services.hamr = {
      Unit = {
        Description = "Hamr launcher daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/hamr";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "graphical-session.target" ];
      };
    };
  };
}
