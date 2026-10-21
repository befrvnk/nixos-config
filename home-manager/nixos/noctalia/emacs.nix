{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  directory = "${config.xdg.stateHome}/noctalia/emacs";
  fonts = config.stylix.fonts;
  opacity = builtins.ceil (config.stylix.opacity.applications * 100);
in
{
  # Only the Home Manager plain-Emacs route. Personal Doom/Spacemacs wrappers
  # deliberately use the raw package and retain their own init/theme settings.
  stylix.targets.emacs.enable = false;
  programs.emacs.extraConfig = ''
    (add-to-list 'default-frame-alist '(alpha-background . ${toString opacity}))
    (set-face-attribute 'default nil :font
      (font-spec :family ${builtins.toJSON fonts.monospace.name} :size ${
        toString (fonts.sizes.terminal * 1.0)
      }))
    (let ((directory ${builtins.toJSON directory}))
      (when (file-readable-p (expand-file-name "noctalia-theme.el" directory))
        (add-to-list 'custom-theme-load-path directory)
        (load-theme 'noctalia t)))
  '';

  # Reuse the shipped theme verbatim but not its profile-discovery/emacsclient
  # hooks: they select Doom first and assume a default daemon we don't configure.
  programs.noctalia.settings.theme.templates.user.emacs = {
    input_path = "${inputs.noctalia}/assets/templates/emacs/emacs.el";
    output_path = "$XDG_STATE_HOME/noctalia/emacs/noctalia-theme.el";
  };

  home.activation.prepareEmacsNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg "${directory}/noctalia-theme.el"} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/emacs.pre-template.el"} \
          --placeholder '(deftheme noctalia "Awaiting native colors.") (provide-theme (quote noctalia))'
      '';
}
