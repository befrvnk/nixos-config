{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
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
    dankMaterialShell = {
      url = "github:AvengeMedia/DankMaterialShell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    vicinae = {
      url = "github:vicinaehq/vicinae";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    niri = {
      url = "github:YaLTeR/niri";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      nixos-hardware,
      zen-browser,
      android-nixpkgs,
      lanzaboote,
      stylix,
      dankMaterialShell,
      vicinae,
      niri,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit nixos-hardware lanzaboote;
          inherit inputs;
        };
        modules = [
          {
            nixpkgs.overlays = [
              android-nixpkgs.overlays.default
              (import ./overlays/niri.nix { inherit niri; })
            ];
          }
          ./hosts/framework/default.nix
          home-manager.nixosModules.home-manager
          stylix.nixosModules.stylix
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              users.frank = import ./home-manager/frank.nix;
              backupFileExtension = "backup";
              sharedModules = [
                stylix.homeModules.stylix
                dankMaterialShell.homeModules.dankMaterialShell.default
                vicinae.homeManagerModules.default
              ];
              extraSpecialArgs = {
                inherit zen-browser;
                inherit android-nixpkgs;
                pkgs-unstable = import nixpkgs-unstable {
                  inherit system;
                  config.allowUnfree = true;
                };
              };
            };
          }
        ];
      };
    };
}
