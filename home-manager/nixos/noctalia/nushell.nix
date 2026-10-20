{
  config,
  lib,
  pkgs,
  ...
}:
{
  # No Nushell entry exists in either pinned catalog. This data-only template
  # uses Noctalia's native renderer, not a second generator/controller/service.
  programs.noctalia.settings.theme.templates.user.nushell = {
    input_path = "${./nushell.nuon}";
    output_path = "$XDG_STATE_HOME/nushell/theme.nuon";
  };

  home.activation.prepareNushellNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/nushell/theme.nuon"} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/nushell.pre-template.nuon"} \
          --placeholder '{}'
      '';
}
