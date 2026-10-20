{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  source = inputs.noctalia-community-templates;
  theme = "${config.xdg.dataHome}/vicinae/themes/noctalia.toml";
  placeholder = ''
    [meta]
    name = "Noctalia"
    description = "Awaiting Noctalia's native template renderer"
    variant = "dark"
    inherits = "vicinae-dark"
  '';
in
{
  # Selecting the same ID in both modes makes upstream's theme-set hook take
  # Vicinae's native rescan/reload branch, not the settings-write branch.
  programs.vicinae.settings.theme = lib.genAttrs [ "dark" "light" ] (_: {
    name = "noctalia";
    icon_theme = "Papirus";
  });

  # Consume only the reviewed, pinned upstream files as a user registration;
  # don't enable mutable catalog downloads or maintain a fork of the template.
  programs.noctalia.settings.theme.templates.user.vicinae = {
    input_path = "${source}/vicinae/vicinae.toml";
    output_path = "$XDG_DATA_HOME/vicinae/themes/noctalia.toml";
    post_hook = "${pkgs.bash}/bin/bash ${source}/vicinae/apply.sh ${inputs.noctalia}/assets/noctalia.svg";
  };

  home.activation.prepareVicinaeNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg theme} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/vicinae.pre-template.toml"} \
          --placeholder ${lib.escapeShellArg placeholder}
      '';
}
