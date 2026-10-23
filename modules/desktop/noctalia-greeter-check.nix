{ configuration, pkgs }:
let
  inherit (pkgs) lib;
  cfg = configuration.config;
  greeter = cfg.services.displayManager.noctalia-greeter;
  reference =
    (configuration.extendModules {
      modules = [
        { services.displayManager.noctalia-greeter.enable = lib.mkForce false; }
      ];
    }).config;
  pamServices = [
    "greetd"
    "login"
    "noctalia"
    "polkit-1"
    "sudo"
    "swaylock"
  ];
  pam = config: lib.genAttrs pamServices (name: config.security.pam.services.${name}.text);
  settingsFile =
    cfg.systemd.tmpfiles.settings."10-noctalia-greeter"."/var/lib/noctalia-greeter/greeter.toml"."L+".argument;
  policy = pkgs.writeText "noctalia-greeter-policy.json" (
    builtins.toJSON {
      inherit settingsFile;
      pam = pam cfg;
      referencePam = pam reference;
      expectedGreetdAuth = [
        "auth required ${pkgs.pam}/lib/security/pam_unix.so"
        "auth optional ${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so"
      ];
      autologin = cfg.services.greetd.settings ? initial_session;
      binary = lib.getExe' greeter.package "noctalia-greeter";
      command = cfg.services.greetd.settings.default_session.command;
      desktops = "${cfg.services.displayManager.sessionData.desktops}";
      frontend = lib.getExe greeter.package;
      keyring = cfg.security.pam.services.greetd.enableGnomeKeyring;
      model = cfg.services.xserver.xkb.model;
      inherit (greeter) passwordlessSyncUsers;
      restartIfChanged = cfg.systemd.services.greetd.restartIfChanged;
      sessionBinPath = lib.makeBinPath cfg.services.displayManager.sessionPackages;
      user = cfg.services.greetd.settings.default_session.user;
      xkbRoot = cfg.services.xserver.xkb.dir;
    }
  );
  keymapProbe =
    pkgs.runCommandCC "noctalia-greeter-keymap-probe"
      {
        nativeBuildInputs = [ pkgs.pkg-config ];
        buildInputs = [ pkgs.libxkbcommon ];
      }
      ''
        mkdir -p $out/bin
        $CC -std=c11 -Wall -Wextra -Werror ${./test-greeter-keymap.c} \
          $(pkg-config --cflags --libs xkbcommon) -o $out/bin/probe
      '';
in
assert lib.assertMsg
  (
    greeter.enable
    && cfg.services.greetd.enable
    && !cfg.services.greetd.useTextGreeter
    && !greeter.settings.auth.allow_empty_password
    && greeter.settings.session.default == "niri"
    && lib.elem "niri" cfg.services.displayManager.sessionData.sessionNames
    && !cfg.systemd.services.greetd.restartIfChanged
    && (cfg.systemd.services.greetd.serviceConfig.StandardInput or "") != "tty"
    && (cfg.systemd.services.greetd.serviceConfig.StandardOutput or "") != "tty"
    && cfg.services.accounts-daemon.enable
    && cfg.security.polkit.enable
    && greeter.passwordlessSyncUsers == [ ]
    && builtins.all (
      name: cfg.security.pam.services.${name}.text == reference.security.pam.services.${name}.text
    ) (builtins.filter (name: name != "greetd") pamServices)
  )
  "Noctalia Greeter must retain password-entry/Niri/recovery defaults and all non-greetd PAM stacks without passwordless sync";
pkgs.runCommand "noctalia-greeter-check"
  {
    GREETER_POLICY = policy;
    GREETER_KEYMAP_PROBE = "${keymapProbe}/bin/probe";
    nativeBuildInputs = [ pkgs.bash ];
  }
  ''
    ${pkgs.python3}/bin/python3 -B ${./test-greeter.py}
    touch $out
  ''
