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
      "https://attic.xuyh0120.win/lantian"
    ];
    trusted-extra-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
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
          noctalia-overview = pkgs.runCommand "noctalia-overview-tests" { } ''
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
              !(cfg.systemd.user.services ? darkman) && !(home.home.activation ? restartDarkman)
            ) "The legacy Darkman controller must be disabled";
            assert pkgs.lib.assertMsg (builtins.all (
              h: !(h.dconf.settings."org/gnome/desktop/interface" ? color-scheme)
            ) variants) "Home Manager must not overwrite Noctalia's runtime color-scheme preference";
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
