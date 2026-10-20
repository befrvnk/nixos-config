{
  config,
  lib,
  pkgs,
  ...
}:
{
  programs.noctalia.settings.theme.templates = {
    enable_builtin_templates = true;
    builtin_ids = [ "ghostty" ];
  };

  # Prepare before either the managed Ghostty config or the enabled Noctalia
  # template is linked. Do not register this runtime output as home.file.
  home.activation.prepareGhosttyNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg "${config.xdg.configHome}/ghostty/themes/noctalia"} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/ghostty-theme.pre-template"}
      '';
}
