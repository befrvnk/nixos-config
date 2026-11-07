{
  config,
  lib,
  pkgs,
  ...
}:
let
  base = pkgs.umbriel;
  launcher = pkgs.writeShellScript "umbriel-session" (
    lib.replaceStrings
      [ "@coreutils@" "@profiles@" "@systemd@" "@umbriel@" "@xkb_root@" ]
      [
        "${pkgs.coreutils}"
        "/etc/profiles/per-user"
        "${pkgs.systemd}"
        "${base}"
        (lib.escapeShellArg config.services.xserver.xkb.dir)
      ]
      (builtins.readFile ./umbriel-session.sh)
  );
  package = pkgs.symlinkJoin {
    name = "umbriel-${base.version}";
    paths = [ base ];
    # Only launcher environment changes. Keep native compositor/unit/portal lifecycle.
    postBuild = ''
      rm $out/bin/start-umbriel
      ln -s ${launcher} $out/bin/start-umbriel
      desktop=$out/share/wayland-sessions/umbriel.desktop
      rm "$desktop"
      cp ${base}/share/wayland-sessions/umbriel.desktop "$desktop"
      chmod u+w "$desktop"
      substituteInPlace "$desktop" \
        --replace-fail 'Exec=${base}/bin/start-umbriel' 'Exec=${launcher}'
    '';
    inherit (base) meta;
    passthru = {
      inherit (base) providedSessions;
      inherit launcher;
    };
  };
in
{
  programs.umbriel = {
    enable = true;
    inherit package;
  };

  environment.systemPackages = [
    pkgs.xdg-utils
  ];
  xdg = {
    autostart.enable = true;
    menus.enable = true;
    mime.enable = true;
    icons.enable = true;
  };

  hardware.graphics.enable = true;

  services.displayManager.sessionPackages = [ package ];

  xdg.portal = {
    enable = true;
    extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    configPackages = [ package ];
  };

  security.polkit.enable = true;

  # Enable gnome-keyring at system level for proper dbus integration
  # PAM configuration in greetd.nix ensures it's unlocked on login
  services.gnome.gnome-keyring.enable = true;

  security.pam.services.swaylock = { };
  programs.dconf.enable = true;
  fonts.enableDefaultPackages = true;
}
