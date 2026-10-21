{
  config,
  lib,
  pkgs,
  ...
}:
{
  stylix.targets.btop.enable = false;
  programs.btop.settings.color_theme = "noctalia";
  programs.noctalia.settings.theme.templates.builtin_ids = [ "btop" ];

  # The native apply hook sees the fixed selector and skips main-config writes.
  # Only the separate theme output is writable; btop reloads it on SIGUSR2.
  home.activation.prepareBtopNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg "${config.xdg.configHome}/btop/themes/noctalia.theme"} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/btop.pre-template.theme"} \
          --placeholder '# Awaiting Noctalia btop colors.'
      '';
}
