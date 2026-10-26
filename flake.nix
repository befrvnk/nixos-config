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
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    cliamp = {
      url = "github:bjarneo/cliamp/main";
      flake = false;
    };
    # CachyOS kernels with a maintained binary cache (nyx-cache.chaotic.cx), replacing
    # nix-cachyos-kernel whose only cache died with the Lantian endpoint (see
    # docs/security-hardening.md). No inputs.nixpkgs.follows: the kernel must be
    # instantiated from Chaotic-Nyx's own nixpkgs pin or its prebuilt paths never match.
    chaotic.url = "github:chaotic-cx/nyx/nyxpkgs-unstable";
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
  # Keys must stay `extra-substituters` / `extra-trusted-public-keys`: Nix does not
  # know `trusted-extra-*` and ignores those silently, so the caches would never be
  # used (checks.cache-trust cannot catch a wrong key name, only a wrong list).
  nixConfig = {
    extra-substituters = [
      "https://nixos.snix.store"
      "https://claude-code.cachix.org"
      "https://devenv.cachix.org"
      "https://niri.cachix.org"
      "https://nix-community.cachix.org"
      "https://noctalia.cachix.org"
      "https://nixos-raspberrypi.cachix.org"
      "https://vicinae.cachix.org"
      "https://nyx-cache.chaotic.cx/?priority=45"
    ];
    extra-trusted-public-keys = [
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "nyx-cache.chaotic.cx:dJxTrgMC3V3cFfyIiBQDQorG6k1LsqurH/srpMSq7qk="
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

      checks = forAllSystems (system: import ./checks { inherit inputs system; });

      # Formatters for `nix fmt` command on supported development systems
      # Use nixfmt-tree so `nix fmt -- --check .` works on the whole repository.
      formatter = forAllSystems (system: inputs.nixpkgs.legacyPackages.${system}.nixfmt-tree);
    };
}
