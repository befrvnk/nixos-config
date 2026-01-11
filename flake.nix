{
  description = "NixOS from Scratch";

  inputs = {
    # Using nixpkgs-unstable as the main channel for latest packages
    # All system and user packages use this channel
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
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
      url = "git+https://codeberg.org/LGFae/awww";
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
    # Pinned nixpkgs for Zed - uses a revision with cached binary
    # Update this when Zed updates and cache.nixos.org has the new version
    # Find cached revisions: check Hydra builds at https://hydra.nixos.org/job/nixpkgs/trunk/zed-editor.x86_64-linux
    nixpkgs-zed.url = "github:NixOS/nixpkgs/1de85f4c808a70f012571ca7ab52a61724f950d8";
  };

  nixConfig = {
    trusted-extra-substituters = [
      "https://nix-community.cachix.org"
      "https://niri.cachix.org"
      "https://vicinae.cachix.org"
      "https://claude-code.cachix.org"
      "https://attic.xuyh0120.win/lantian"
    ];
    trusted-extra-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
      "vicinae.cachix.org-1:1kDrfienkGHPYbkpNj1mWTr7Fm1+zcenzgTizIcI3oc="
      "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      "lantian:EeAUQ+W+6r7EtwnmYjeVwx5kOGEBpjlBfPlzGlTNvHc="
    ];
  };

  outputs =
    inputs:
    let
      system = "x86_64-linux";
      pkgs = inputs.nixpkgs.legacyPackages.${system};

      # Host configuration helper
      hostLib = import ./lib/hosts.nix { inherit inputs; };
    in
    {
      nixosConfigurations = {
        # Framework Laptop 13 (AMD AI 300 series)
        framework = hostLib.mkHost {
          hostname = "framework";
          cpuVendor = "amd";
          hasFingerprint = true;
          hasTouchscreen = false;
        };

        # Future hosts (uncomment when ready):
        #
        # surface = hostLib.mkHost {
        #   hostname = "surface";
        #   cpuVendor = "intel";
        #   hasFingerprint = false;
        #   hasTouchscreen = true;
        # };
        #
        # dell = hostLib.mkHost {
        #   hostname = "dell";
        #   cpuVendor = "intel";
        #   hasFingerprint = true;
        #   hasTouchscreen = false;
        # };
      };

      # Formatter for `nix fmt` command
      formatter.${system} = pkgs.nixfmt;
    };
}
