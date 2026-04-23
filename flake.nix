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
    # Don't use inputs.nixpkgs.follows here - vicinae cachix has builds
    # for the flake's own nixpkgs version, using follows causes cache misses
    vicinae.url = "github:vicinaehq/vicinae";
    vicinae-extensions = {
      url = "github:vicinaehq/extensions";
      inputs.vicinae.follows = "vicinae";
    };
    # Don't use inputs.nixpkgs.follows here - niri cachix has builds
    # for the flake's own nixpkgs version, using follows causes cache misses
    niri.url = "github:sodiboo/niri-flake";
    awww = {
      url = "git+https://codeberg.org/LGFae/awww?ref=refs/tags/v0.12.0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Don't use inputs.nixpkgs.follows here - the pinned overlay requires
    # the flake's own nixpkgs version to get binary cache hits
    nix-cachyos-kernel.url = "github:xddxdd/nix-cachyos-kernel/release";
    # JetBrains IDE plugins (for NixIDEA in IntelliJ IDEA)
    nix-jetbrains-plugins = {
      url = "github:nix-community/nix-jetbrains-plugins";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # TUI for AI coding agents
    # Temporarily pinned to last known working revision until upstream fixes
    # the missing `glob` dependency regression in the shared package split.
    opencode = {
      url = "github:anomalyco/opencode/e14e874e513178ac056cec7be5bac4ff5fd842ef";
    };
    # Don't use inputs.nixpkgs.follows here - devenv cachix has builds
    # for the flake's own nixpkgs version, and its nix fork requires matching nixpkgs
    devenv.url = "github:cachix/devenv";
    # Terminal session manager for AI coding agents
    agent-of-empires = {
      url = "github:njbrake/agent-of-empires";
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

  nixConfig = {
    trusted-extra-substituters = [
      "https://claude-code.cachix.org"
      "https://devenv.cachix.org"
      "https://niri.cachix.org"
      "https://nix-community.cachix.org"
      "https://vicinae.cachix.org"
      "https://attic.xuyh0120.win/lantian"
    ];
    trusted-extra-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
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

      nixosConfigurations = inputs.nixpkgs.lib.mapAttrs (_: hostLib.mkHost) hostInventory.nixos;

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
          pi-extension-tests = pkgs.runCommand "pi-extension-tests" { } ''
            test_files="$(${pkgs.findutils}/bin/find ${./home-manager/shared/pi/extensions} \( -name '*.test.ts' -o -name '*.test.mjs' \) | ${pkgs.coreutils}/bin/sort | ${pkgs.gnused}/bin/sed ':a;N;$!ba;s/\n/ /g')"
            ${pkgs.tsx}/bin/tsx --test $test_files
            touch $out
          '';

          inherit (pkgs)
            gh-enhance
            kotlin-lsp
            pi-coding-agent
            user-scanner
            ;
        }
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          inherit (pkgs)
            domain-check
            idea-community
            orca-ai
            ;
        }
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
          inherit (pkgs)
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
