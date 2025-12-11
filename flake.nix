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
    vicinae = {
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vicinae-extensions = {
      url = "github:vicinaehq/extensions";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        vicinae.follows = "vicinae";
      };
    };
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    awww = {
      url = "git+https://codeberg.org/LGFae/awww";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    claude-code = {
      url = "github:sadjow/claude-code-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
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
      formatter.${system} = pkgs.nixfmt-rfc-style;
    };
}
