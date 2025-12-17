{
  pkgs,
  lib,
  config,
  ...
}:

let
  # Wrapper scripts using --init-directory for profile switching
  doom-emacs = pkgs.writeShellScriptBin "doom-emacs" ''
    exec ${pkgs.emacs-pgtk}/bin/emacs --init-directory="$HOME/.config/emacs-doom" "$@"
  '';

  spacemacs = pkgs.writeShellScriptBin "spacemacs" ''
    exec ${pkgs.emacs-pgtk}/bin/emacs --init-directory="$HOME/.config/emacs-spacemacs" "$@"
  '';

  # Doom CLI wrapper for doom sync, doom upgrade, etc.
  doom = pkgs.writeShellScriptBin "doom" ''
    exec "$HOME/.config/emacs-doom/bin/doom" "$@"
  '';
in
{
  programs.emacs = {
    enable = true;
    package = pkgs.emacs-pgtk;
  };

  home.packages = [
    # Wrapper scripts
    doom-emacs
    spacemacs
    doom

    # Dependencies for all distributions
    pkgs.ripgrep
    pkgs.sqlite
    pkgs.graphviz
    pkgs.pandoc
    pkgs.texliveSmall

    # Doom Emacs specific
    pkgs.cmake
    pkgs.libtool
    pkgs.libvterm
  ];

  # Auto-clone Emacs distributions on first activation
  home.activation = {
    cloneDoomEmacs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${config.home.homeDirectory}/.config/emacs-doom" ]; then
        ${pkgs.git}/bin/git clone --depth 1 https://github.com/doomemacs/doomemacs \
          "${config.home.homeDirectory}/.config/emacs-doom"
        echo "Doom Emacs cloned. Run 'doom install' to complete setup."
      fi
    '';

    cloneSpacemacs = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      if [ ! -d "${config.home.homeDirectory}/.config/emacs-spacemacs" ]; then
        ${pkgs.git}/bin/git clone https://github.com/syl20bnr/spacemacs \
          "${config.home.homeDirectory}/.config/emacs-spacemacs"
        echo "Spacemacs cloned. First run will bootstrap automatically."
      fi
    '';
  };
}
