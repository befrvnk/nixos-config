{
  inputs,
  hostConfig,
  ...
}:

{
  home-manager = {
    backupFileExtension = "hm-backup";
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${hostConfig.primaryUser} = {
      imports = [
        ../../home-manager/nixos/frank.nix
        ../../home-manager/nixos/umbriel
      ];
    };
    sharedModules = [
      inputs.stylix.homeModules.stylix
      inputs.vicinae.homeManagerModules.default
      inputs.niri.homeModules.niri

      # Home Manager uses the system pkgs set; keep Stylix from defining
      # Home Manager-local nixpkgs overlays that are ignored/deprecated with
      # useGlobalPkgs.
      { stylix.overlays.enable = false; }
    ];
    extraSpecialArgs = {
      inherit inputs hostConfig;
      # Upstream module fetched as a flake input; taking it from pkgs.umbriel.src
      # would import from a derivation output, which `nix flake check --no-build` forbids.
      umbrielHomeModule = inputs.umbriel + "/nix/home-module.nix";
    };
  };
}
