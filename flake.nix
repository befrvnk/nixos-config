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
                NOCTALIA_BIN = "${inputs.noctalia.packages.${system}.default}/bin/noctalia";
                NOCTALIA_SOURCE = inputs.noctalia.outPath;
                QT5_PROBE = "${probe "5" qt5}/bin/probe";
                QT6_PROBE = "${probe "6" qt6}/bin/probe";
                QT5_PLUGIN_PATH = "${pkgs.libsForQt5.qt5ct}/${qt5.qtPluginPrefix}:${qt5}/${qt5.qtPluginPrefix}";
                QT6_PLUGIN_PATH = "${pkgs.qt6Packages.qt6ct}/${qt6.qtPluginPrefix}:${qt6}/${qt6.qtPluginPrefix}";
                QT5_CONFIG_SOURCE = home.xdg.configFile."qt5ct/qt5ct.conf".source;
                QT6_CONFIG_SOURCE = home.xdg.configFile."qt6ct/qt6ct.conf".source;
                MANAGED_CONFIG_HOME = home.xdg.configHome;
                NIRI_VALIDATOR = "${pkgs.niri}/bin/niri";
                NIRI_CONFIG = pkgs.writeText "niri-test-config.kdl" home.programs.niri.finalConfig;
                NIRI_NODES = pkgs.writeText "niri-test-nodes.json" (builtins.toJSON home.programs.niri.config);
                FZF_WRAPPER = "${
                  pkgs.callPackage ./home-manager/nixos/noctalia/fzf-package.nix {
                    configHome = home.xdg.configHome;
                  }
                }/bin/fzf";
                NUSHELL_CLI = "${pkgs.nushell}/bin/nu";
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
            assert pkgs.lib.assertMsg (same (
              map (h: builtins.toJSON h.systemd.user.services.noctalia-theme) variants
            )) "The theme bridge must not restart itself during app-theme activation";
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
