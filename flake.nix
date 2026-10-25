{
  description = "NixOS from Scratch";

  inputs = {
    # Using nixpkgs-unstable as the main channel for latest packages
    # All system and user packages use this channel
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-index-database = {
      url = "github:nix-community/nix-index-database";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    android-nixpkgs = {
      url = "github:tadfisher/android-nixpkgs/stable";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";
    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stylix = {
      url = "github:nix-community/stylix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Keep upstream nixpkgs for Vicinae's binary cache; match the macOS cask release.
    vicinae.url = "github:vicinaehq/vicinae/v0.29.2";
    vicinae-extensions = {
      url = "github:vicinaehq/extensions/ee117bc64f341ed71b4a27e311f343b12a75f43d";
      inputs.vicinae.follows = "vicinae";
    };
    # Don't use inputs.nixpkgs.follows here - niri cachix has builds
    # for the flake's own nixpkgs version, using follows causes cache misses
    niri.url = "github:sodiboo/niri-flake";
    # Native C++ Noctalia V5; keep its nixpkgs pin for upstream cache hits.
    noctalia.url = "github:noctalia-dev/noctalia/v5.3.0";
    noctalia-community-plugins = {
      url = "github:noctalia-dev/community-plugins/bd834815ee5da2ed744a9cbf1425342a4eecba6f";
      flake = false;
    };
    noctalia-community-templates = {
      url = "github:noctalia-dev/community-templates/7aae018927ae35d007734868388c34c901870f45";
      flake = false;
    };
    # Upstream sources for the Umbriel Home Manager module. Importing the module from
    # pkgs.umbriel.src would read a derivation output during evaluation, which
    # `nix flake check --no-build` rejects (read-only mode, IFD disabled).
    # The revision must match nixpkgs' umbriel source: scripts/update-umbriel.sh re-pins it
    # during `devenv flake-update`, and the umbriel-trial check asserts the two agree.
    umbriel = {
      url = "github:noctalia-dev/umbriel/5cea311e7e7d6eba3ea41f5c4ca826971340f7cc";
      flake = false;
    };
    awww = {
      url = "git+https://codeberg.org/LGFae/awww?ref=refs/tags/v0.12.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Quickshell flakes are not on GitHub; follows nixpkgs to stay on one channel
    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # QML plugin wiring niri IPC into Quickshell; provides a quickshell-with-plugin build
    qml-niri = {
      url = "github:imiric/qml-niri/main";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell";
    };
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cliamp = {
      url = "github:bjarneo/cliamp/main";
      flake = false;
    };
    # Don't use inputs.nixpkgs.follows here - the pinned overlay requires
    # the flake's own nixpkgs version to get binary cache hits
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    # User-local project development environment registry
    shellpin = {
      url = "github:befrvnk/shellpin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Review-first terminal diff viewer
    hunk = {
      url = "github:modem-dev/hunk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Git worktree management CLI
    worktrunk = {
      url = "github:max-sixty/worktrunk/v0.36.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # macOS system configuration
    nix-darwin = {
      url = "github:nix-darwin/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  # NOTE: nixConfig values must be literal (Nix rejects thunks here), so these
  # lists are kept in sync manually with the single source of truth in
  # ./shared/caches.nix (used by modules/system/core.nix at runtime).
  nixConfig = {
    trusted-extra-substituters = [
      "https://nixos.snix.store"
      "https://claude-code.cachix.org"
      "https://devenv.cachix.org"
      "https://niri.cachix.org"
      "https://nix-community.cachix.org"
      "https://noctalia.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://vicinae.cachix.org"
    ];
    trusted-extra-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
    ];
  };

  outputs =
    inputs:
    let
      systems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];
      forAllSystems = inputs.nixpkgs.lib.genAttrs systems;

      # Host configuration helpers
      hostLib = import ./lib/hosts.nix { inherit inputs; };
      darwinLib = import ./lib/darwin.nix { inherit inputs; };
      hostInventory = import ./lib/host-inventory.nix;
      overlayLib = import ./lib/overlays.nix { inherit inputs; };
    in
    {
      # System configurations generated from the host inventory.
      darwinConfigurations = inputs.nixpkgs.lib.mapAttrs (_: darwinLib.mkDarwinHost) hostInventory.darwin;

      nixosConfigurations = (inputs.nixpkgs.lib.mapAttrs (_: hostLib.mkHost) hostInventory.nixos) // {
        hermi = inputs.nixos-raspberrypi.lib.nixosSystem {
          system = "aarch64-linux";
          specialArgs = {
            inherit inputs;
            inherit (inputs) nixos-raspberrypi;
          };
          modules = [
            ./hosts/hermi
          ];
        };
      };

      checks = forAllSystems (
        system:
        let
          pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays =
              if inputs.nixpkgs.lib.hasSuffix "darwin" system then
                overlayLib.darwinOverlays
              else
                overlayLib.nixosOverlays;
          };
        in
        {
          cache-trust =
            let
              shared = import ./shared/caches.nix;
              declared = (import ./flake.nix).nixConfig;
              runtime =
                if pkgs.stdenv.hostPlatform.isLinux then
                  inputs.self.nixosConfigurations.framework.config.nix.settings
                else
                  { };
              safe =
                value: !(pkgs.lib.hasInfix "attic.xuyh0120.win" value) && !(pkgs.lib.hasPrefix "lantian:" value);
              values =
                shared.substituters
                ++ shared.publicKeys
                ++ (runtime.substituters or [ ])
                ++ (runtime.trusted-public-keys or [ ])
                ++ (runtime.extra-substituters or [ ])
                ++ (runtime.extra-trusted-public-keys or [ ]);
            in
            assert pkgs.lib.assertMsg (
              declared.trusted-extra-substituters == shared.substituters
              && declared.trusted-extra-public-keys == shared.publicKeys
            ) "Flake cache literals must match shared cache policy";
            assert pkgs.lib.assertMsg (builtins.all safe values)
              "The compromised Lantian endpoint and signing key must not be trusted";
            pkgs.runCommand "cache-trust-check" { } ''
              touch $out
            '';

          home-cleanup = pkgs.callPackage ./pkgs/home-cleanup/package.nix { };

          pi-extension-tests = pkgs.runCommand "pi-extension-tests" { } ''
            test_files="$(${pkgs.findutils}/bin/find ${./home-manager/shared/pi/extensions} \( -name '*.test.ts' -o -name '*.test.mjs' \) | ${pkgs.coreutils}/bin/sort | ${pkgs.gnused}/bin/sed ':a;N;$!ba;s/\n/ /g')"
            ${pkgs.tsx}/bin/tsx --test --test-concurrency=1 $test_files
            touch $out
          '';

          pi-package-smoke = pkgs.runCommand "pi-package-smoke" { } ''
            PI_BIN=${pkgs.pi-coding-agent}/bin/pi \
              ${pkgs.bash}/bin/bash ${./scripts/smoke-test-pi-package.sh} ${./home-manager/shared/pi}
            touch $out
          '';

          inherit (pkgs)
            cliamp
            gh-enhance
            kleinanzeigen
            kotlin-lsp
            pi-coding-agent
            user-scanner
            ;
        }
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          kernel-provider-compat =
            let
              framework = inputs.self.nixosConfigurations.framework;
              provider = inputs.nix-cachyos-kernel.inputs.nixpkgs.legacyPackages.${system};
              standard = framework.extendModules {
                modules = [
                  ({ lib, pkgs, ... }: { boot.kernelPackages = lib.mkForce pkgs.linuxPackages; })
                ];
              };
              aggregator = packages: (packages.aggregateModules [ ]).drvPath;
            in
            assert pkgs.lib.assertMsg (
              aggregator framework.pkgs == aggregator provider
            ) "Pinned CachyOS modules must use their provider's matching aggregation format";
            assert pkgs.lib.assertMsg (
              aggregator standard.pkgs == aggregator pkgs
            ) "Standard kernels must retain main nixpkgs' certificate-aware aggregation";
            pkgs.runCommand "kernel-provider-compat-check" { } ''
              touch $out
            '';

          umbriel-trial =
            let
              # A `flake = false` input only exposes its source path, so read the pin from the lock.
              umbrielRev = (builtins.fromJSON (builtins.readFile ./flake.lock)).nodes.umbriel.locked.rev;
            in
            assert pkgs.lib.assertMsg (
              umbrielRev == (pkgs.umbriel.src.drvAttrs.rev or "")
            ) "umbriel flake input must match the umbriel source pinned by nixpkgs";
            import ./modules/desktop/umbriel-check.nix {
              configuration = inputs.self.nixosConfigurations.framework;
              inherit pkgs;
            };

          noctalia-greeter = import ./modules/desktop/noctalia-greeter-check.nix {
            configuration = inputs.self.nixosConfigurations.framework;
            inherit pkgs;
          };

          noctalia-lock-auth =
            let
              cfg = inputs.self.nixosConfigurations.framework.config;
              home = cfg.home-manager.users.frank;
              lines = builtins.filter (line: line != "") (
                pkgs.lib.splitString "\n" cfg.security.pam.services.noctalia.text
              );
              expected = [
                "auth required ${pkgs.pam}/lib/security/pam_unix.so"
                "account required ${pkgs.pam}/lib/security/pam_unix.so"
              ];
            in
            assert pkgs.lib.assertMsg (lines == expected)
              "Native locker password PAM must require pam_unix without fingerprint, nullok or permissive modules";
            assert pkgs.lib.assertMsg (
              home.programs.noctalia.settings.lockscreen.enabled
              && home.programs.noctalia.settings.lockscreen.lock_before_suspend
              && home.programs.noctalia.settings.lockscreen.grace_period_seconds == 0
              && !home.programs.noctalia.settings.lockscreen.allow_empty_password
              && !home.programs.noctalia.settings.lockscreen.blurred_desktop
              && home.programs.noctalia.settings.lockscreen.transition == [ ]
              && home.programs.noctalia.settings.lockscreen.monitors == [ ]
              && home.programs.swaylock.enable
              && !home.services.swayidle.enable
              && !(builtins.hasAttr "swayidle" home.systemd.user.services)
              && home.programs.noctalia.settings.idle.pre_action_fade_seconds == 0
              &&
                home.programs.noctalia.settings.idle.behavior_order == [
                  "lock"
                  "screen-off"
                  "suspend"
                ]
              &&
                home.programs.noctalia.settings.idle.behavior.lock == {
                  action = "lock";
                  enabled = true;
                  locked_timeout = 0;
                  timeout = 300;
                }
              &&
                home.programs.noctalia.settings.idle.behavior.screen-off == {
                  action = "screen_off";
                  enabled = true;
                  locked_timeout = 0;
                  timeout = 305;
                }
              &&
                home.programs.noctalia.settings.idle.behavior.suspend == {
                  action = "lock_and_suspend";
                  enabled = true;
                  locked_timeout = 0;
                  timeout = 310;
                }
              && builtins.any (patch: pkgs.lib.hasSuffix "suspend-lock-policy.patch" (toString patch)) (
                home.programs.noctalia.package.patches or [ ]
              )
              && pkgs.lib.hasPrefix "/nix/store/" (
                builtins.head home.programs.niri.settings.binds."Mod+Shift+S".action.spawn
              )
              &&
                home.programs.noctalia.settings.shell.session.power.suspend
                == "${builtins.head home.programs.niri.settings.binds."Mod+Shift+S".action.spawn} --require-lock"
              && builtins.all (
                action: action.action != "suspend"
              ) home.programs.noctalia.settings.shell.session.actions
              &&
                home.programs.niri.settings.binds."Mod+Shift+X".action.spawn == [
                  "${home.programs.noctalia.package}/bin/noctalia"
                  "msg"
                  "session"
                  "lock"
                ]
              && pkgs.lib.elem "timeout=10" cfg.security.pam.services.login.rules.auth.fprintd.args
              && pkgs.lib.elem "max-tries=3" cfg.security.pam.services.login.rules.auth.fprintd.args
            ) "Native automatic locking must retain secure defaults, timing and one pre-sleep/logind owner";
            pkgs.runCommand "noctalia-lock-auth-check" { } ''
              touch $out
            '';

          noctalia-tray-anchor = import ./home-manager/nixos/noctalia/tray-anchor-check.nix {
            inherit pkgs;
            source = inputs.noctalia.outPath;
            patches =
              inputs.self.nixosConfigurations.framework.config.home-manager.users.frank.programs.noctalia.package.patches;
          };

          noctalia-bar-geometry = import ./home-manager/nixos/noctalia/bar-geometry-check.nix {
            inherit pkgs;
            source = inputs.noctalia.outPath;
            patches =
              inputs.self.nixosConfigurations.framework.config.home-manager.users.frank.programs.noctalia.package.patches;
          };

          noctalia-battery-warning = import ./home-manager/nixos/noctalia/battery-warning-check.nix {
            inherit pkgs;
            source = inputs.noctalia.outPath;
            patches =
              inputs.self.nixosConfigurations.framework.config.home-manager.users.frank.programs.noctalia.package.patches;
          };

          noctalia-overview =
            let
              home = inputs.self.nixosConfigurations.framework.config.home-manager.users.frank;
              qt5 = pkgs.qt5.qtbase;
              qt6 = pkgs.qt6.qtbase;
              vscodeTheme = builtins.head (
                builtins.filter (
                  extension: (extension.vscodeExtUniqueId or "") == "noctalia.noctaliatheme"
                ) home.programs.vscode.profiles.default.extensions
              );
              vicinaeProbe =
                pkgs.runCommandCC "noctalia-vicinae-theme-probe"
                  {
                    nativeBuildInputs = [ pkgs.pkg-config ];
                    buildInputs = [
                      qt6
                      pkgs.tomlplusplus
                    ];
                  }
                  ''
                    mkdir -p $out/bin
                    source=${inputs.vicinae}/src/server/src
                    mkdir -p include
                    ln -s ${pkgs.tomlplusplus}/include/toml++ include/tomlplusplus
                    $CXX -std=c++23 -include bits/stdc++.h -ffunction-sections -fdata-sections \
                      -Wl,--gc-sections -Iinclude -I$source -I$source/utils \
                      -I${inputs.vicinae}/src/lib/common/include \
                      ${./home-manager/nixos/noctalia/test_vicinae_theme.cpp} \
                      $source/theme/theme-parser.cpp $source/theme/theme-file.cpp \
                      $(pkg-config --cflags --libs Qt6Gui) -o $out/bin/probe
                  '';
              probe =
                major: qtbase:
                pkgs.runCommandCC "noctalia-qt${major}-probe"
                  {
                    nativeBuildInputs = [ pkgs.pkg-config ];
                    buildInputs = [ qtbase ];
                  }
                  ''
                    mkdir -p $out/bin
                    $CXX -std=c++17 -fPIC ${./home-manager/nixos/noctalia/test_qt_palette.cpp} \
                      $(pkg-config --cflags --libs Qt${major}Widgets) -o $out/bin/probe
                  '';
            in
            pkgs.runCommand "noctalia-overview-tests"
              {
                NOCTALIA_BIN = "${home.programs.noctalia.package}/bin/noctalia";
                NOCTALIA_SOURCE = inputs.noctalia.outPath;
                NATIVE_BAR_STYLE = pkgs.writeText "noctalia-bar-style.json" (
                  builtins.toJSON {
                    bar = home.programs.noctalia.settings.bar.main;
                    widget = home.programs.noctalia.settings.widget;
                    font = home.programs.noctalia.settings.shell.font_family;
                    patches = map builtins.baseNameOf home.programs.noctalia.package.patches;
                  }
                );
                ACTIVATION_COREUTILS = "${pkgs.coreutils}";
                ACTIVATION_SYSTEMCTL = "${pkgs.systemd}/bin/systemctl";
                ACTIVATION_UTIL_LINUX = "${pkgs.util-linux}";
                NOCTALIA_OVERVIEW_ENSURE = pkgs.writeText "noctalia-overview-ensure.sh" home.home.activation.noctaliaOverviewEnsure.data;
                NOCTALIA_THEME_REQUEST = pkgs.writeText "noctalia-theme-request-hook.sh" home.home.activation.noctaliaThemeRequest.data;
                ACTIVATION_THEME_REQUEST = pkgs.lib.last home.programs.noctalia.settings.hooks.theme_mode_changed;
                NOCTALIA_WALLPAPER_POLICY = pkgs.writeText "noctalia-wallpaper-policy.json" (
                  builtins.toJSON {
                    hooks = home.programs.noctalia.settings.hooks;
                    script = builtins.head home.programs.noctalia.settings.hooks.theme_mode_changed;
                    wallpapers = import ./home-manager/nixos/wallpapers;
                    bridgeEnvironment = home.systemd.user.services.noctalia-theme.Service.Environment;
                    userUnits = builtins.attrNames home.systemd.user.services;
                  }
                );
                NOCTALIA_THEME_SERVICE = pkgs.writeText "noctalia-theme-service.json" (
                  builtins.toJSON home.systemd.user.services.noctalia-theme
                );
                QT5_PROBE = "${probe "5" qt5}/bin/probe";
                QT6_PROBE = "${probe "6" qt6}/bin/probe";
                QT5_PLUGIN_PATH = "${pkgs.libsForQt5.qt5ct}/${qt5.qtPluginPrefix}:${qt5}/${qt5.qtPluginPrefix}";
                QT6_PLUGIN_PATH = "${pkgs.qt6Packages.qt6ct}/${qt6.qtPluginPrefix}:${qt6}/${qt6.qtPluginPrefix}";
                QT5_CONFIG_SOURCE = home.xdg.configFile."qt5ct/qt5ct.conf".source;
                QT6_CONFIG_SOURCE = home.xdg.configFile."qt6ct/qt6ct.conf".source;
                MANAGED_CONFIG_HOME = home.xdg.configHome;
                NATIVE_LOCK_POLICY = pkgs.writeText "native-lock-trial.json" (
                  builtins.toJSON {
                    configSource = "${home.xdg.configFile."noctalia/config.toml".source}";
                    screen = home.programs.noctalia.settings.lockscreen;
                    session = home.programs.noctalia.settings.shell.session;
                    manualSuspend = home.programs.niri.settings.binds."Mod+Shift+S".action.spawn;
                    swayidleEnabled = home.services.swayidle.enable;
                    userUnits = builtins.attrNames home.systemd.user.services;
                    idle = home.programs.noctalia.settings.idle;
                    manual = home.programs.niri.settings.binds."Mod+Shift+X".action.spawn;
                    fallback = home.programs.swaylock.enable;
                    passwordPam = inputs.self.nixosConfigurations.framework.config.security.pam.services.noctalia.text;
                  }
                );
                GTKSOURCE_TEMPLATE = home.programs.noctalia.settings.theme.templates.user.gtksourceview.input_path;
                GTKSOURCE_ORIGINAL_TEMPLATE = "${inputs.stylix}/modules/gtksourceview/template.xml.mustache";
                GTKSOURCE_PROBE = ./home-manager/nixos/noctalia/probe-gtksourceview.py;
                GTKSOURCE4_LIB = "${pkgs.lib.getLib pkgs.gtksourceview4}/lib/libgtksourceview-4.so.0";
                GTKSOURCE5_LIB = "${pkgs.lib.getLib pkgs.gtksourceview5}/lib/libgtksourceview-5.so.0";
                GTKSOURCE_LINKS = pkgs.writeText "gtksourceview-test-links.json" (
                  builtins.toJSON (
                    map (version: toString home.xdg.dataFile."gtksourceview-${version}/styles/stylix.xml".source) [
                      "2.0"
                      "3.0"
                      "4"
                      "5"
                    ]
                  )
                );
                MANAGED_HOME = home.home.homeDirectory;
                XRDB_CLI = "${pkgs.xrdb}/bin/xrdb";
                XVFB_CLI = "${pkgs.xorg-server}/bin/Xvfb";
                XRESOURCES_MAIN = home.home.file.${home.xresources.path}.source;
                XRESOURCES_TEMPLATE = ./home-manager/nixos/noctalia/xresources.template;
                XRESOURCES_HOOK = home.programs.noctalia.settings.theme.templates.user.xresources.post_hook;
                EMACS_CLI = "${pkgs.emacs-pgtk}/bin/emacs";
                EMACS_MANAGED_INIT = pkgs.writeText "emacs-test-managed-init.el" home.programs.emacs.extraConfig;
                EMACS_ROUTES = pkgs.writeText "emacs-test-routes.json" (
                  builtins.toJSON (
                    map
                      (package: {
                        inherit (package) name;
                        path = "${package}/bin/${package.name}";
                      })
                      (
                        builtins.filter (
                          package:
                          pkgs.lib.elem package.name [
                            "doom-emacs"
                            "spacemacs"
                          ]
                        ) home.home.packages
                      )
                  )
                );
                BTOP_CLI = "${pkgs.btop}/bin/btop";
                BTOP_CONFIG = home.xdg.configFile."btop/btop.conf".source;
                BRIGHTNESS_CONTROL_SCRIPT = ./home-manager/nixos/niri/brightness-ctl.sh;
                OSD_INTEGRATION = pkgs.writeText "native-osd-integration.json" (
                  builtins.toJSON {
                    osd = home.programs.noctalia.settings.osd;
                    audio = home.programs.noctalia.settings.audio;
                    binds = builtins.intersectAttrs {
                      XF86AudioRaiseVolume = null;
                      XF86AudioLowerVolume = null;
                      XF86AudioMute = null;
                      XF86MonBrightnessUp = null;
                      XF86MonBrightnessDown = null;
                    } home.programs.niri.settings.binds;
                    startup = home.programs.niri.settings.spawn-at-startup;
                  }
                );
                NIRI_VALIDATOR = "${pkgs.niri}/bin/niri";
                NIRI_CONFIG = pkgs.writeText "niri-test-config.kdl" home.programs.niri.finalConfig;
                NIRI_NODES = pkgs.writeText "niri-test-nodes.json" (builtins.toJSON home.programs.niri.config);
                FZF_WRAPPER = "${
                  pkgs.callPackage ./home-manager/nixos/noctalia/fzf-package.nix {
                    configHome = home.xdg.configHome;
                  }
                }/bin/fzf";
                NUSHELL_CLI = "${pkgs.nushell}/bin/nu";
                NU_MANAGED_CONFIG = home.home.file."${home.xdg.configHome}/nushell/config.nu".source;
                NUSHELL_THEME_TEMPLATE = ./home-manager/nixos/noctalia/nushell.nuon;
                NUSHELL_THEME_READER = ./home-manager/nixos/noctalia/nushell-theme.nu;
                FZF_REGISTRATION = pkgs.writeText "fzf-test-template.json" (
                  builtins.toJSON home.programs.noctalia.settings.theme.templates.user.fzf
                );
                LAZYGIT_CLI = "${pkgs.lazygit}/bin/lazygit";
                LAZYGIT_WRAPPER = "${home.programs.lazygit.package}/bin/lazygit";
                LAZYGIT_BASE = home.home.file."${home.xdg.configHome}/lazygit/config.yml".source;
                LAZYGIT_REGISTRATION = pkgs.writeText "lazygit-test-template.json" (
                  builtins.toJSON home.programs.noctalia.settings.theme.templates.user.lazygit
                );
                VICINAE_PROBE = "${vicinaeProbe}/bin/probe";
                COMMUNITY_TEMPLATE_SOURCE = inputs.noctalia-community-templates.outPath;
                VICINAE_SETTINGS = pkgs.writeText "vicinae-test-settings.json" (
                  builtins.toJSON home.programs.vicinae.settings
                );
                ZED_SETTINGS = pkgs.writeText "zed-test-settings.json" (
                  builtins.toJSON home.programs.zed-editor.userSettings
                );
                ZED_SETTINGS_ACTIVATION = pkgs.writeText "zed-test-activation.sh" home.home.activation.zedSettingsActivation.data;
                MANAGED_STATE_HOME = home.xdg.stateHome;
                STARSHIP_CLI = "${pkgs.starship}/bin/starship";
                STARSHIP_TEMPLATE = home.programs.noctalia.settings.theme.templates.user.starship.input_path;
                STARSHIP_BASE = home.home.file.${home.programs.starship.configPath}.source;
                STARSHIP_POINTERS = pkgs.writeText "starship-test-pointers.json" (
                  builtins.toJSON {
                    session = home.home.sessionVariables.STARSHIP_CONFIG;
                    nushell = home.programs.nushell.environmentVariables.STARSHIP_CONFIG;
                    entry = home.programs.noctalia.settings.theme.templates.user.starship;
                  }
                );
                VSCODE_EXTENSION = "${vscodeTheme}/share/vscode/extensions/noctalia.noctaliatheme";
                VSCODE_CLI = "${pkgs.vscode}/bin/code";
                VSCODE_SETTINGS = home.home.file."${home.xdg.configHome}/Code/User/settings.json".source;
                VSCODE_TEMPLATE = pkgs.writeText "vscode-test-template.json" (
                  builtins.toJSON home.programs.noctalia.settings.theme.templates.user.vscode
                );
                ZEN_CHROME_ENTRY = home.home.file.".zen/default/chrome/userChrome.css".source;
                ZEN_CONTENT_ENTRY = home.home.file.".zen/default/chrome/userContent.css".source;
                ZEN_POLICY_PACKAGE = home.programs.zen-browser.package.unwrapped;
                ZEN_PACKAGE_BIN = "${home.programs.zen-browser.package}/bin/zen-beta";
                ZEN_LAUNCHER = "${
                  builtins.head (builtins.filter (p: p.name == "zen-launch") home.home.packages)
                }/bin/zen-launch";
                ZEN_INTEGRATION = pkgs.writeText "zen-test-integration.json" (
                  builtins.toJSON {
                    policies = home.programs.zen-browser.policies;
                    chrome = home.programs.noctalia.settings.theme.templates.user.zen_browser_chrome;
                    content = home.programs.noctalia.settings.theme.templates.user.zen_browser_content;
                    launcher = home.xdg.desktopEntries.zen-browser.exec;
                  }
                );
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.coreutils
                  pkgs.diffutils
                  pkgs.git
                  pkgs.gnugrep
                  pkgs.gnused
                ];
              }
              ''
                ${pkgs.python3}/bin/python3 -B -m unittest discover \
                  -s ${./home-manager/nixos/noctalia} -p 'test_*.py'
                touch $out
              '';
          noctalia-theme-invariants =
            let
              cfg = inputs.self.nixosConfigurations.framework.config;
              home = cfg.home-manager.users.frank;
              variants = [
                home
                home.specialisation.dark.configuration
                home.specialisation.light.configuration
              ];
              same = values: builtins.length (pkgs.lib.unique values) == 1;
              managedConfig =
                h: path:
                builtins.any (
                  file: file.target == ".config/${path}" || file.target == "${h.xdg.configHome}/${path}"
                ) (builtins.attrValues h.home.file);
              managedGhosttyTheme = h: name: managedConfig h "ghostty/themes/${name}";
            in
            assert pkgs.lib.assertMsg (same (
              map (h: toString h.xdg.configFile."noctalia/config.toml".source) variants
            )) "Noctalia config must not change across app-theme specialisations";
            assert pkgs.lib.assertMsg (same (
              map (h: builtins.toJSON h.systemd.user.services.noctalia) variants
            )) "App-theme switches must not restart Noctalia";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.systemd.user.services.noctalia-theme) variants)
              && builtins.all (h: h.systemd.user.services.noctalia-theme.Service.Type == "exec") variants
            ) "Bridge units must stay constant and report startup before waiting for Home Manager";
            assert pkgs.lib.assertMsg (builtins.all (
              h:
              pkgs.lib.elem "NOCTALIA_ACTIVATION_LOCK=${h.xdg.stateHome}/noctalia/theme-activation.lock" h.systemd.user.services.noctalia-theme.Service.Environment
              && pkgs.lib.hasInfix "${h.xdg.stateHome}/noctalia/theme-activation.lock" h.home.activation.noctaliaThemeLock.data
            ) variants) "Boot activation and the bridge must share a persistent pre-session-safe lock path";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.systemd.user.services.noctalia-overview) variants)
              && builtins.all (
                h:
                pkgs.lib.elem "graphical-session.target" h.systemd.user.services.noctalia-overview.Install.WantedBy
                && pkgs.lib.elem "reloadSystemd" h.home.activation.noctaliaOverviewEnsure.after
                && pkgs.lib.hasInfix "--no-block start noctalia-overview.service" h.home.activation.noctaliaOverviewEnsure.data
              ) variants
            ) "Overview watcher must recover after rebuilds without restarting the shell";
            assert pkgs.lib.assertMsg (
              !(cfg.systemd.user.services ? darkman) && !(home.home.activation ? restartDarkman)
            ) "The legacy Darkman controller must be disabled";
            assert pkgs.lib.assertMsg (builtins.all (
              h: !(h.dconf.settings."org/gnome/desktop/interface" ? color-scheme)
            ) variants) "Home Manager must not overwrite Noctalia's runtime color-scheme preference";
            assert pkgs.lib.assertMsg (builtins.all (
              h:
              pkgs.lib.toList h.programs.ghostty.settings.theme == [ "noctalia" ]
              && pkgs.lib.elem "ghostty" h.programs.noctalia.settings.theme.templates.builtin_ids
              && !(managedGhosttyTheme h "noctalia")
              && !(managedGhosttyTheme h "stylix-dark")
              && !(managedGhosttyTheme h "stylix-light")
            ) variants) "Ghostty must select the native template and leave its output runtime-writable";
            assert pkgs.lib.assertMsg (builtins.all (
              h:
              !h.stylix.targets.gtk.enable
              && h.gtk.theme == null
              && h.gtk.gtk4.theme == null
              && !(h.dconf.settings."org/gnome/desktop/interface" ? gtk-theme)
              && h.gtk.font.name == h.stylix.fonts.sansSerif.name
              && h.gtk.font.size == h.stylix.fonts.sizes.applications
              && h.gtk.iconTheme.name == "Papirus"
              && h.gtk.cursorTheme.name == h.stylix.cursor.name
              &&
                builtins.all
                  (
                    version:
                    h.xdg.configFile."gtk-${version}/gtk.css".text == ''@import url("noctalia.css");''
                    && !(managedConfig h "gtk-${version}/noctalia.css")
                  )
                  [
                    "3.0"
                    "4.0"
                  ]
              && builtins.all (id: pkgs.lib.elem id h.programs.noctalia.settings.theme.templates.builtin_ids) [
                "gtk3"
                "gtk4"
              ]
            ) variants) "GTK must preserve assets, use native writable colors and avoid preference conflicts";
            assert pkgs.lib.assertMsg (
              cfg.qt.enable
              && cfg.qt.platformTheme == "qt5ct"
              && builtins.all (
                h:
                !h.stylix.targets.qt.enable
                && pkgs.lib.elem "qt" h.programs.noctalia.settings.theme.templates.builtin_ids
                &&
                  builtins.all
                    (
                      version:
                      let
                        path = "qt${version}ct";
                        text = h.xdg.configFile."${path}/${path}.conf".text;
                      in
                      pkgs.lib.hasInfix "custom_palette=true" text
                      && pkgs.lib.hasInfix "color_scheme_path=${h.xdg.configHome}/${path}/colors/noctalia.conf" text
                      && pkgs.lib.hasInfix "style=Fusion" text
                      && !(managedConfig h "${path}/colors/noctalia.conf")
                    )
                    [
                      "5"
                      "6"
                    ]
              ) variants
            ) "Qt must select the native writable palettes without changing platform integration";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.programs.vicinae.settings) variants)
              && same (map (h: builtins.toJSON h.systemd.user.services.vicinae) variants)
              && builtins.all (
                h:
                h.programs.vicinae.settings.theme.dark.name == "noctalia"
                && h.programs.vicinae.settings.theme.light.name == "noctalia"
                && h.programs.vicinae.settings.theme.dark.icon_theme == "Papirus"
                && h.programs.vicinae.settings.theme.light.icon_theme == "Papirus"
                && h.programs.noctalia.settings.theme.templates.user ? vicinae
                && !(h.programs.vicinae.themes ? stylix)
                && !(h.xdg.dataFile ? "vicinae/themes/noctalia.toml")
              ) variants
            ) "Vicinae must reload a native runtime theme without mode-specific config or unit changes";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.programs.zed-editor.userSettings) variants)
              && builtins.all (
                h:
                !h.stylix.targets.zed.enable
                && h.programs.zed-editor.mutableUserSettings
                &&
                  h.programs.zed-editor.userSettings.theme == {
                    mode = "system";
                    dark = "Noctalia Dark";
                    light = "Noctalia Light";
                  }
                && h.programs.zed-editor.userSettings.buffer_font_family == h.stylix.fonts.monospace.name
                && h.programs.zed-editor.userSettings.ui_font_family == h.stylix.fonts.sansSerif.name
                && h.programs.noctalia.settings.theme.templates.user ? zed
                && !(h.programs.zed-editor.themes ? stylix)
                && !(managedConfig h "zed/themes/noctalia.json")
              ) variants
            ) "Zed must keep constant settings/fonts and select the writable native theme family";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.programs.zen-browser.policies) variants)
              && builtins.all (
                h:
                !h.stylix.targets.zen-browser.enable
                &&
                  h.programs.zen-browser.policies.Preferences."toolkit.legacyUserProfileCustomizations.stylesheets"
                  == {
                    Value = true;
                    Status = "locked";
                  }
                && h.xdg.desktopEntries.zen-browser.exec == "zen-launch %U"
                &&
                  builtins.all
                    (
                      part:
                      let
                        entry = h.programs.noctalia.settings.theme.templates.user."zen_browser_${part}";
                      in
                      !(entry ? post_hook) && !(entry ? pre_hook) && !(entry ? post_action)
                    )
                    [
                      "chrome"
                      "content"
                    ]
                &&
                  pkgs.lib.hasInfix "${h.xdg.stateHome}/noctalia/zen-browser/zen-userChrome.css"
                    h.home.file.".zen/default/chrome/userChrome.css".text
                &&
                  pkgs.lib.hasInfix "${h.xdg.stateHome}/noctalia/zen-browser/zen-userContent.css"
                    h.home.file.".zen/default/chrome/userContent.css".text
              ) variants
            ) "Zen must keep declarative profile imports/policies and never run profile-mutating hooks";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.programs.vscode.profiles.default.userSettings) variants)
              && builtins.all (
                h:
                h.programs.vscode.enable
                && !h.stylix.targets.vscode.enable
                && h.programs.vscode.profiles.default.userSettings."workbench.colorTheme" == "NoctaliaTheme"
                && !h.programs.vscode.profiles.default.userSettings."window.autoDetectColorScheme"
                && !h.programs.vscode.profiles.default.userSettings."extensions.autoUpdate"
                && h.programs.noctalia.settings.theme.templates.user ? vscode
                && !(h.programs.noctalia.settings.theme.templates.user.vscode ? post_hook)
                && builtins.all (
                  ext: (ext.vscodeExtUniqueId or "") != "stylix.stylix"
                ) h.programs.vscode.profiles.default.extensions
              ) variants
            ) "VS Code must keep declarative settings/extension metadata and writable native palette data";
            assert pkgs.lib.assertMsg
              (
                same (map (h: toString h.programs.lazygit.package) variants)
                && builtins.all (
                  h:
                  h.programs.lazygit.enable
                  && h.programs.lazygit.enableNushellIntegration
                  && !h.stylix.targets.lazygit.enable
                  && !(h.programs.lazygit.settings.gui ? theme)
                  && h.programs.noctalia.settings.theme.templates.user ? lazygit
                  && !(h.programs.noctalia.settings.theme.templates.user.lazygit ? post_hook)
                  && !(managedConfig h "lazygit/themes/noctalia.yml")
                ) variants
              )
              "lazygit must overlay native runtime colors without rewriting its managed base or shell integration";
            assert pkgs.lib.assertMsg
              (
                same (map (h: toString h.programs.fzf.package) variants)
                && builtins.all (
                  h:
                  !h.programs.fzf.enable
                  && !h.stylix.targets.fzf.enable
                  && h.programs.fzf.colors == { }
                  && !(h.home.sessionVariables ? FZF_DEFAULT_OPTS)
                  && h.programs.noctalia.settings.theme.templates.user ? fzf
                  && !(h.programs.noctalia.settings.theme.templates.user.fzf ? post_hook)
                  && !(managedConfig h "fzf/themes/noctalia.sh")
                  && pkgs.lib.elem h.programs.fzf.package h.home.packages
                ) variants
              )
              "fzf must consume native community colors per process without shell integration or global env changes";
            assert pkgs.lib.assertMsg (
              same (map (h: h.programs.niri.finalConfig) variants)
              && builtins.all (
                h:
                h.programs.niri.settings.layout.border.enable
                && h.programs.niri.settings.layout.border.width == 4
                && h.programs.niri.settings.layout.border.active == null
                && h.programs.niri.settings.layout.border.inactive == null
                && !h.programs.niri.settings.layout.focus-ring.enable
                && !h.programs.niri.settings.layout.shadow.enable
                && h.programs.niri.settings.layout.background-color == "transparent"
                && h.programs.niri.settings.layout.gaps == 12
                && h.programs.niri.settings.overview.zoom == 0.5
                && !h.programs.niri.settings.overview.workspace-shadow.enable
                && pkgs.lib.elem "niri" h.programs.noctalia.settings.theme.templates.builtin_ids
                && !(managedConfig h "niri/noctalia.kdl")
              ) variants
            ) "Niri must keep its layout/overview unchanged while only native colors vary at runtime";
            assert pkgs.lib.assertMsg
              (
                same (map (h: h.programs.nushell.extraConfig) variants)
                && builtins.all (
                  h:
                  !h.stylix.targets.nushell.enable
                  && h.programs.noctalia.settings.theme.templates.user ? nushell
                  && !(h.programs.noctalia.settings.theme.templates.user.nushell ? post_hook)
                  && !(managedConfig h "nushell/theme-dark.nuon")
                  && !(managedConfig h "nushell/theme-light.nuon")
                  && pkgs.lib.hasInfix "refresh-nushell-theme" h.programs.nushell.extraConfig
                ) variants
              )
              "Nushell must read Noctalia's runtime data without prebuilt color files or prompt integration changes";
            assert pkgs.lib.assertMsg
              (builtins.all (
                h:
                h.programs.noctalia.settings.wallpaper.enabled
                && !h.programs.noctalia.settings.backdrop.enabled
                && h.programs.noctalia.settings.backdrop.blur_intensity == 0.0
                && h.programs.noctalia.settings.backdrop.tint_intensity == 0.0
                && h.programs.noctalia.settings.wallpaper.transition == [ "fade" ]
                && h.programs.noctalia.settings.wallpaper.transition_duration == 1000
                && !h.programs.noctalia.settings.wallpaper.automation.enabled
                && builtins.length h.programs.noctalia.settings.hooks.theme_mode_changed == 2
                && builtins.elem (builtins.head h.programs.noctalia.settings.hooks.theme_mode_changed) h.programs.noctalia.settings.hooks.started
                && !(builtins.any (pkgs.lib.hasPrefix "NOCTALIA_WALLPAPER_") h.systemd.user.services.noctalia-theme.Service.Environment)
                && !(h.systemd.user.services ? noctalia-wallpaper)
                && builtins.all (
                  favorite: builtins.attrNames favorite == [ "path" ]
                ) h.programs.noctalia.settings.wallpaper.favorite
                && !(builtins.any (package: pkgs.lib.hasPrefix "awww-" package.name) h.home.packages)
                && !(h.systemd.user.services ? monitor-hotplug)
                && !(pkgs.lib.hasInfix "awww-daemon" h.programs.niri.finalConfig)
                && builtins.any (
                  rule:
                  (rule.place-within-backdrop or false) == true
                  && builtins.any (match: (match.namespace or "") == "^noctalia-wallpaper$") rule.matches
                ) h.programs.niri.settings.layer-rules
              ) variants)
              "Noctalia must render a single backdrop wallpaper and select its pair through native hooks, not the theme worker";
            assert pkgs.lib.assertMsg
              (
                same (map (h: builtins.toJSON h.programs.starship.settings) variants)
                && builtins.all (
                  h:
                  h.programs.starship.enable
                  && h.programs.starship.enableNushellIntegration
                  && !h.stylix.targets.starship.enable
                  && h.programs.starship.settings.palette == "noctalia"
                  && !((h.programs.starship.settings.palettes or { }) ? base16)
                  && h.home.sessionVariables.STARSHIP_CONFIG == "${h.xdg.stateHome}/noctalia/starship.toml"
                  &&
                    h.programs.nushell.environmentVariables.STARSHIP_CONFIG == h.home.sessionVariables.STARSHIP_CONFIG
                  && !(h.programs.noctalia.settings.theme.templates.user.starship ? post_hook)
                ) variants
              )
              "Starship must render native palette data without rewriting its declarative base or prompt integrations";
            assert pkgs.lib.assertMsg (builtins.all
              (
                h:
                !h.services.swayosd.enable
                && !(h.systemd.user.services ? swayosd)
                && h.programs.noctalia.settings.osd.enabled
                && h.programs.noctalia.settings.osd.position == "bottom_center"
                && h.programs.noctalia.settings.osd.position_vertical == "bottom_center"
                && builtins.all (n: !(builtins.hasAttr "F${toString n}" h.programs.niri.settings.binds)) (
                  pkgs.lib.range 1 12
                )
                && h.programs.noctalia.settings.osd.kinds.volume
                && h.programs.noctalia.settings.osd.kinds.volume_output
                && !h.programs.noctalia.settings.osd.kinds.volume_input
                && h.programs.noctalia.settings.osd.kinds.brightness
                && !h.programs.noctalia.settings.audio.enable_overdrive
                && !(pkgs.lib.hasInfix "swayosd-client" h.programs.niri.finalConfig)
                && !(pkgs.lib.hasInfix "volume-ctl" h.programs.niri.finalConfig)
                && pkgs.lib.hasInfix "pw-loopback" h.programs.niri.finalConfig
              )
              variants
            ) "Native Noctalia must own output/brightness OSD while preserving Framework audio initialization";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.programs.btop.settings) variants)
              && builtins.all (
                h:
                h.programs.btop.enable
                && !h.stylix.targets.btop.enable
                && h.programs.btop.settings.color_theme == "noctalia"
                && h.programs.btop.settings.update_ms == 1000
                && !h.programs.btop.settings.vim_keys
                && !(h.programs.btop.themes ? stylix)
                && pkgs.lib.elem "btop" h.programs.noctalia.settings.theme.templates.builtin_ids
                && !(managedConfig h "btop/themes/noctalia.theme")
              ) variants
            ) "btop must retain declarative settings/key behavior with only native runtime colors";
            assert pkgs.lib.assertMsg
              (
                same (map (h: toString h.programs.emacs.finalPackage) variants)
                && same (map (h: h.programs.emacs.extraConfig) variants)
                && builtins.all (
                  h:
                  h.programs.emacs.enable
                  && !h.stylix.targets.emacs.enable
                  && h.programs.noctalia.settings.theme.templates.user ? emacs
                  && !(h.programs.noctalia.settings.theme.templates.user.emacs ? post_hook)
                  && pkgs.lib.hasInfix "(load-theme 'noctalia t)" h.programs.emacs.extraConfig
                  && !(pkgs.lib.hasInfix "base16-stylix" h.programs.emacs.extraConfig)
                  && !h.services.emacs.enable
                ) variants
              )
              "Managed plain Emacs must load native theme data without changing personal profiles or requiring a daemon";
            assert pkgs.lib.assertMsg
              (builtins.all (
                h:
                builtins.all (target: !h.stylix.targets.${target}.enable) [
                  "blender"
                  "forge"
                  "gdu"
                  "gedit"
                  "kde"
                  "vencord"
                ]
                && !(builtins.any (
                  name:
                  pkgs.lib.hasPrefix "blender/" name
                  || pkgs.lib.hasPrefix "forge/" name
                  || pkgs.lib.hasPrefix "gdu/" name
                  || pkgs.lib.hasPrefix "Vencord/" name
                ) (builtins.attrNames h.xdg.configFile))
                && !(h.xdg.dataFile ? "gedit/styles/stylix.xml")
                && !(pkgs.lib.hasInfix "stylix-kde-config" (h.home.sessionVariables.XDG_CONFIG_DIRS or ""))
                && h.programs.noctalia.settings.theme.templates.user ? xresources
                && h.programs.noctalia.settings.theme.templates.user ? gtksourceview
                && h.programs.swaylock.enable
              ) variants)
              "Dormant theme generators/KDE overlay must be retired without dropping xterm, shared editor styles or the lock screen";
            assert pkgs.lib.assertMsg (
              same (map (h: builtins.toJSON h.xresources.properties) variants)
              && builtins.all (
                h:
                !h.stylix.targets.xresources.enable
                && !h.stylix.targets.sxiv.enable
                && h.xresources.properties."*.faceName" == h.stylix.fonts.monospace.name
                && h.xresources.properties."*.faceSize" == toString h.stylix.fonts.sizes.terminal
                && h.xresources.properties."Xcursor.theme" == h.stylix.cursor.name
                && h.xresources.properties."Xcursor.size" == h.stylix.cursor.size
                && !(h.xresources.properties ? "*background")
                && !(h.xresources.properties ? "*foreground")
                && pkgs.lib.hasInfix "${h.xdg.stateHome}/noctalia/Xresources" h.xresources.extraConfig
              ) variants
            ) "Xresources must keep fonts/cursor declarative and load only native runtime color data";
            assert pkgs.lib.assertMsg
              (builtins.all (
                h:
                !h.stylix.targets.gtksourceview.enable
                && h.programs.noctalia.settings.theme.templates.user ? gtksourceview
                && !(h.programs.noctalia.settings.theme.templates.user.gtksourceview ? post_hook)
                && builtins.all (version: h.xdg.dataFile ? "gtksourceview-${version}/styles/stylix.xml") [
                  "2.0"
                  "3.0"
                  "4"
                  "5"
                ]
              ) variants)
              "GTKSourceView must preserve legacy scheme lookup with native runtime colors, not app preference rewrites";
            pkgs.runCommand "noctalia-theme-invariants" { } ''
              touch $out
            '';

          safe-suspend =
            pkgs.runCommand "safe-suspend-tests"
              {
                nativeBuildInputs = [
                  pkgs.bash
                  pkgs.jq
                ];
              }
              ''
                ${pkgs.python3}/bin/python3 -B -m unittest discover \
                  -s ${./home-manager/nixos/niri} -p 'test_safe_suspend.py'
                touch $out
              '';

          inherit (pkgs)
            domain-check
            idea-community
            ;
        }
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          falcon-observer = pkgs.callPackage ./pkgs/falcon-observer/package.nix { };

          inherit (pkgs)
            google-antigravity
            openchamber
            supacode
            ;
        }
      );

      # Formatters for `nix fmt` command on supported development systems
      # Use nixfmt-tree so `nix fmt -- --check .` works on the whole repository.
      formatter = forAllSystems (system: inputs.nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
