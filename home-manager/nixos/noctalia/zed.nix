{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  fonts = config.stylix.fonts;
  placeholder = builtins.toJSON {
    name = "Noctalia";
    author = "Noctalia";
    themes =
      map
        (mode: {
          name = "Noctalia ${if mode == "dark" then "Dark" else "Light"}";
          appearance = mode;
          style = { };
        })
        [
          "dark"
          "light"
        ];
  };
in
{
  # Noctalia renders both palette variants; Zed follows the native system mode.
  # Keep the font settings that disabling the Stylix target would otherwise drop.
  stylix.targets.zed.enable = false;
  programs.zed-editor.userSettings = {
    buffer_font_family = fonts.monospace.name;
    buffer_font_size = fonts.sizes.terminal * 4.0 / 3.0;
    ui_font_family = fonts.sansSerif.name;
    ui_font_size = fonts.sizes.applications * 4.0 / 3.0;
    theme = {
      mode = "system";
      dark = "Noctalia Dark";
      light = "Noctalia Light";
    };
  };

  # Register only the pinned upstream Zed output, not its optional Gram entry.
  # The upstream family contains opaque and transparent variants; select opaque.
  programs.noctalia.settings.theme.templates.user.zed = {
    input_path = "${inputs.noctalia-community-templates}/zed/zed.json";
    output_path = "$XDG_CONFIG_HOME/zed/themes/noctalia.json";
  };

  home.activation.prepareZedNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg "${config.xdg.configHome}/zed/themes/noctalia.json"} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/zed.pre-template.json"} \
          --placeholder ${lib.escapeShellArg placeholder}
      '';
}
