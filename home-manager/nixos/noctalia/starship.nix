{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.starship;
  runtime = "${config.xdg.stateHome}/noctalia/starship.toml";
  base = config.home.file.${cfg.configPath}.source;
  template = pkgs.runCommand "noctalia-starship-template.toml" { } ''
    cat ${base} > $out
    printf '\n' >> $out
    cat ${inputs.noctalia}/assets/templates/starship/starship.toml >> $out
  '';
in
{
  stylix.targets.starship.enable = false;
  programs = {
    starship.settings.palette = "noctalia";
    nushell.environmentVariables.STARSHIP_CONFIG = runtime;
    noctalia.settings.theme.templates.user.starship = {
      input_path = "${template}";
      output_path = "$XDG_STATE_HOME/noctalia/starship.toml";
    };
  };
  # Starship has no include directive. Keep the declarative base managed, then
  # render base + the unmodified shipped palette as its complete runtime config.
  home.sessionVariables.STARSHIP_CONFIG = lib.mkForce runtime;

  assertions = [
    {
      assertion = !(builtins.hasAttr "noctalia" (cfg.settings.palettes or { }));
      message = "The Noctalia Starship palette is runtime-owned; keep custom settings in the declarative base.";
    }
  ];

  noctalia.prepareOutputs = [
    {
      theme = runtime;
      backup = "${config.xdg.stateHome}/noctalia/starship.pre-template.toml";
      placeholder = "# Awaiting Noctalia Starship palette.";
    }
  ];
}
