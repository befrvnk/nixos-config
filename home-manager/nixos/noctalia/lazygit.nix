{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  base = "${config.xdg.configHome}/lazygit/config.yml";
  theme = "${config.xdg.configHome}/lazygit/themes/noctalia.yml";
  package = pkgs.symlinkJoin {
    name = "lazygit-noctalia";
    inherit (pkgs.lazygit) meta version;
    paths = [ pkgs.lazygit ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram "$out/bin/lazygit" \
        --set-default LG_CONFIG_FILE ${lib.escapeShellArg "${base},${theme}"}
    '';
  };
in
{
  stylix.targets.lazygit.enable = false;
  programs.lazygit = {
    inherit package;
    # Retain a managed base file even when there are no other user options.
    # Native lazygit loads it first and overlays the generated theme second.
    settings.gui = { };
  };

  # The upstream hook rewrites config.yml through its protected symlink. Use
  # native multi-file loading instead, leaving the upstream color input intact.
  programs.noctalia.settings.theme.templates.user.lazygit = {
    input_path = "${inputs.noctalia-community-templates}/lazygit/lazygit.yml";
    output_path = "$XDG_CONFIG_HOME/lazygit/themes/noctalia.yml";
  };

  home.activation.prepareLazygitNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg theme} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/lazygit.pre-template.yml"} \
          --placeholder '{}'
      '';
}
