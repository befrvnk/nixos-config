{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  runtime = "${config.xdg.stateHome}/noctalia/gtksourceview/stylix.xml";
  # Keep the maintained syntax/style definitions and legacy scheme ID; only
  # translate color placeholders for Noctalia's native renderer.
  roles = {
    base00 = "background";
    base01 = "surface_container_low";
    base02 = "surface_container";
    base03 = "outline_variant";
    base04 = "on_surface_variant";
    base05 = "on_surface";
    base06 = "on_surface";
    base07 = "on_surface";
    base08 = "error";
    base09 = "terminal_bright_yellow";
    base0A = "tertiary";
    base0B = "terminal_normal_green";
    base0C = "terminal_normal_cyan";
    base0D = "primary";
    base0E = "secondary";
    base0F = "terminal_bright_red";
  };
  names = builtins.attrNames roles;
  source = builtins.readFile "${inputs.stylix}/modules/gtksourceview/template.xml.mustache";
  template = pkgs.writeText "noctalia-gtksourceview-template.xml" (
    lib.replaceStrings ((map (name: "#{{${name}-hex}}") names) ++ [ ''_name="Stylix"'' ]) (
      (map (name: "{{colors.${roles.${name}}.default.hex}}") names) ++ [ ''_name="Noctalia"'' ]
    ) source
  );
  versions = [
    "2.0"
    "3.0"
    "4"
    "5"
  ];
in
{
  stylix.targets.gtksourceview.enable = false;
  # Out-of-store data links keep the manager's search paths stable while
  # Noctalia owns one writable XML file. No app settings or source code is run.
  xdg.dataFile = lib.genAttrs' versions (version: {
    name = "gtksourceview-${version}/styles/stylix.xml";
    value.source = config.lib.file.mkOutOfStoreSymlink runtime;
  });
  programs.noctalia.settings.theme.templates.user.gtksourceview = {
    input_path = "${template}";
    output_path = "$XDG_STATE_HOME/noctalia/gtksourceview/stylix.xml";
  };
  home.activation.prepareGtksourceviewNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg runtime} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/gtksourceview.pre-template.xml"} \
          --placeholder '<style-scheme id="stylix" _name="Noctalia" version="1.0"></style-scheme>'
      '';
}
