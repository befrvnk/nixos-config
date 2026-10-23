{
  config,
  lib,
  pkgs,
  ...
}:
let
  greeter = config.services.displayManager.noctalia-greeter;
  keyboard = config.services.xserver.xkb;
  session = pkgs.writeShellScript "noctalia-greeter-environment" ''
    export XDG_DATA_DIRS=${lib.escapeShellArg "${config.services.displayManager.sessionData.desktops}/share"}:"''${XDG_DATA_DIRS:-/run/current-system/sw/share:/usr/local/share:/usr/share}"
    export XKB_CONFIG_ROOT=${lib.escapeShellArg keyboard.dir}
    export XKB_DEFAULT_MODEL=${lib.escapeShellArg keyboard.model}
    export PATH=${lib.escapeShellArg (lib.makeBinPath config.services.displayManager.sessionPackages)}:"$PATH"
    exec ${lib.getExe greeter.package} ${lib.escapeShellArgs greeter.extraArgs}
  '';
in
{
  services.displayManager.noctalia-greeter = {
    enable = true;
    # Appearance sync keeps its normal administrator-authenticated policy.
    passwordlessSyncUsers = [ ];
    settings = {
      auth.allow_empty_password = false;
      keyboard = {
        inherit (keyboard) layout options variant;
      };
      session.default = "niri";
    };
  };

  services.greetd = {
    enable = true;
    useTextGreeter = false;
    settings.default_session = {
      command = "${session}";
      user = "greeter";
    };
  };

  security.pam.services.greetd = {
    enableGnomeKeyring = true;
    # The login substack and direct fingerprint rules can succeed without ever
    # consuming the typed password. Only greetd auth is replaced: session/account/
    # password management still include login, and other PAM services are untouched.
    rules.auth = lib.mkIf greeter.enable (
      lib.mkForce {
        unix = {
          order = 12000;
          control = "required";
          modulePath = "${pkgs.pam}/lib/security/pam_unix.so";
        };
        gnome_keyring = {
          order = 12200;
          control = "optional";
          modulePath = "${pkgs.gnome-keyring}/lib/security/pam_gnome_keyring.so";
        };
      }
    );
  };
}
