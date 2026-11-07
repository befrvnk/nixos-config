{ configuration, pkgs }:
let
  inherit (pkgs) lib;
  cfg = configuration.config;
  home = cfg.home-manager.users.frank;
  reference =
    (configuration.extendModules {
      modules = [ { programs.umbriel.enable = lib.mkForce false; } ];
    }).config;
  variants = [
    home
    home.specialisation.dark.configuration
    home.specialisation.light.configuration
  ];
  same = values: builtins.length (lib.unique values) == 1;
  pamNames = [
    "greetd"
    "login"
    "noctalia"
    "polkit-1"
    "sudo"
    "swaylock"
  ];
  policy = pkgs.writeText "umbriel-session-policy.json" (
    builtins.toJSON {
      config = "${home.xdg.configFile."umbriel/config.toml".source}";
      configHome = home.xdg.configHome;
      settings = home.programs.umbriel.settings;
      launcher = "${cfg.programs.umbriel.package.launcher}";
      package = "${cfg.programs.umbriel.package}";
      source = "${pkgs.umbriel.src}";
      originalBindings =
        builtins.attrNames
          (import ../../home-manager/nixos/umbriel/bindings.nix {
            config = home;
            inherit pkgs;
          }).binds;
      noctorTemplate = home.programs.noctalia.settings.theme.templates.user.umbriel;
      native = "${home.programs.noctalia.package}/bin/noctalia";
      sessions = "${cfg.services.displayManager.sessionData.desktops}";
      safeSuspend = lib.removeSuffix " --require-lock" home.programs.noctalia.settings.shell.session.power.suspend;
      overviewConditions = home.systemd.user.services.noctalia-overview.Unit.ConditionEnvironment;
      portal = "${cfg.programs.umbriel.portalPackage}";
      portalRouting = home.xdg.portal.config.umbriel;
      coreutils = "${pkgs.coreutils}";
      systemd = "${pkgs.systemd}/bin/systemctl";
      homeVars = "${home.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";
    }
  );
in
assert lib.assertMsg
  (
    cfg.programs.umbriel.enable
    && cfg.services.displayManager.noctalia-greeter.settings.session.default == "umbriel"
    && lib.elem "umbriel" cfg.services.displayManager.sessionData.sessionNames
    && builtins.all (
      name: cfg.security.pam.services.${name}.text == reference.security.pam.services.${name}.text
    ) pamNames
    &&
      home.programs.noctalia.settings.bar
      == reference.home-manager.users.frank.programs.noctalia.settings.bar
    &&
      home.programs.noctalia.settings.idle
      == reference.home-manager.users.frank.programs.noctalia.settings.idle
    &&
      home.programs.noctalia.settings.lockscreen
      == reference.home-manager.users.frank.programs.noctalia.settings.lockscreen
    && cfg.services.logind.settings == reference.services.logind.settings
    && !home.services.swayidle.enable
    && same (map (h: toString h.xdg.configFile."umbriel/config.toml".source) variants)
    && !(home.programs.noctalia.settings.theme.templates.user.umbriel ? post_hook)
  )
  "The Umbriel session must preserve default/PAM/idle/lock/lid/bar policy and keep immutable config constant across theme variants";
pkgs.runCommand "umbriel-session-check"
  {
    UMBRIEL_POLICY = policy;
    nativeBuildInputs = [ pkgs.bash ];
  }
  ''
    ${pkgs.python3}/bin/python3 -B ${./test-umbriel.py}
    touch $out
  ''
