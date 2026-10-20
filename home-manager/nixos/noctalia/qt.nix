{
  config,
  lib,
  pkgs,
  ...
}:
let
  fonts = config.stylix.fonts;
  versions = [
    "5"
    "6"
  ];
  qtct = version: "qt${version}ct";
in
{
  # System Qt already installs both qtct plugins and exports qt5ct (also an
  # accepted Qt6ct alias). Keep that integration instead of adding another owner.
  stylix.targets.qt.enable = lib.mkForce false;
  programs.noctalia.settings.theme.templates.builtin_ids = [ "qt" ];

  xdg.configFile = lib.genAttrs' versions (version: {
    name = "${qtct version}/${qtct version}.conf";
    value.text = ''
      [Appearance]
      color_scheme_path=${config.xdg.configHome}/${qtct version}/colors/noctalia.conf
      custom_palette=true
      icon_theme=${config.gtk.iconTheme.name}
      style=Fusion
      [Fonts]
      fixed="${fonts.monospace.name},${toString fonts.sizes.applications}"
      general="${fonts.sansSerif.name},${toString fonts.sizes.applications}"
    '';
  });

  # Old Noctalia color files may be read-only. As with Ghostty/GTK, back up
  # and privatize only the outputs; keep the main configs declarative.
  home.activation.prepareQtNoctaliaThemes =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      (
        lib.concatMapStringsSep "\n" (version: ''
          $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
            ${lib.escapeShellArg "${config.xdg.configHome}/${qtct version}/colors/noctalia.conf"} \
            ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/${qtct version}.pre-template.conf"} \
            --placeholder '[ColorScheme]'
        '') versions
      );
}
