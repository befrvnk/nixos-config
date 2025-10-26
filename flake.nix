{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
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
    };
  };

  outputs = { nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, zen-browser, android-nixpkgs, ... }@inputs: {
    nixosConfigurations.framework = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit nixos-hardware; };
      modules = [
        {
          nixpkgs.overlays = [
            inputs.android-nixpkgs.overlays.default
          ];
        }
        ./hosts/framework/default.nix
        home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            users.frank = import ./home-manager/frank.nix;
            backupFileExtension = "backup";
            extraSpecialArgs = {
              inherit zen-browser;
              inherit android-nixpkgs;
              pkgs-unstable = import nixpkgs-unstable {
                system = "x86_64-linux";
                config.allowUnfree = true;
              };
            };
          };
        }
      ];
    };
  };
}
