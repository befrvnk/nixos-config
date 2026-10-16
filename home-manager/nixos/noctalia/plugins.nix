{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  source = inputs.noctalia-community-plugins;
  noctalia = config.programs.noctalia.package;
  # Export only the reviewed plugins, not the entire community collection.
  plugins = pkgs.runCommand "noctalia-reviewed-plugins" { } ''
    ${lib.getExe noctalia} plugins lint ${source}/udiskie ${source}/lid-guard
    ${pkgs.python3}/bin/python3 -B ${source}/udiskie/tests/check_translations.py
    mkdir -p $out
    ln -s ${source}/udiskie $out/udiskie
    ln -s ${source}/lid-guard $out/lid-guard
  '';
in
{
  programs.noctalia.settings = {
    plugins = {
      auto_update = "none";
      enabled = [
        "8bury/lid-guard"
        "aristides/udiskie"
      ];
      source = [
        {
          name = "official";
          kind = "git";
          location = "https://github.com/noctalia-dev/official-plugins";
          enabled = true;
        }
        {
          # Avoid duplicate copies from the mutable community source.
          name = "community";
          kind = "git";
          location = "https://github.com/noctalia-dev/community-plugins";
          enabled = false;
        }
        {
          name = "nix-reviewed";
          kind = "path";
          location = "${plugins}";
          enabled = true;
        }
      ];
    };
  };

  # Noctalia's subprocesses must find their tools without relying on an
  # interactive shell's PATH. Keep the user profile/system paths for xdg-open.
  systemd.user.services.noctalia.Service.Environment = [
    "PATH=${
      lib.makeBinPath [
        noctalia
        pkgs.bash
        pkgs.coreutils
        pkgs.dconf
        pkgs.glib
        pkgs.systemd
        pkgs.udiskie
        pkgs.udisks
        pkgs.xdg-utils
      ]
    }:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
  ];
}
