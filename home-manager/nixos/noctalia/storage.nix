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
  # Export only the reviewed plugin, not the entire community collection.
  plugins = pkgs.runCommand "noctalia-udiskie-plugin" { } ''
    ${lib.getExe noctalia} plugins lint ${source}/udiskie
    ${pkgs.python3}/bin/python3 -B ${source}/udiskie/tests/check_translations.py
    mkdir -p $out
    ln -s ${source}/udiskie $out/udiskie
  '';
in
{
  programs.noctalia.settings = {
    plugins = {
      auto_update = "none";
      enabled = [ "aristides/udiskie" ];
      source = [
        {
          name = "official";
          kind = "git";
          location = "https://github.com/noctalia-dev/official-plugins";
          enabled = true;
        }
        {
          # Avoid a second copy of this plugin from the mutable community source.
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
    plugin_settings."aristides/udiskie" = {
      # The existing udiskie daemon owns automount and event notifications.
      enable_notifications = false;
      auto_open_filemanager = false;
      file_manager_cmd = "xdg-open";
    };
    widget.storage = {
      type = "aristides/udiskie:status";
      hide_when_empty = true;
      show_count = true;
      color = "on_surface";
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
        pkgs.udiskie
        pkgs.udisks
        pkgs.xdg-utils
      ]
    }:${config.home.profileDirectory}/bin:/run/current-system/sw/bin"
  ];
}
