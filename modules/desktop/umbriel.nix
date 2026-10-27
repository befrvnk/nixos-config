{
  config,
  lib,
  pkgs,
  ...
}:
let
  base = pkgs.umbriel;
  launcher = pkgs.writeShellScript "umbriel-trial-session" (
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
    name = "umbriel-trial-${base.version}";
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
  # Retained dual-session setup: Greeter keeps Niri default until a new request.
}
