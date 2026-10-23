{
  inputs,
  hostConfig,
  pkgs,
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
      umbrielHomeModule = pkgs.umbriel.src + "/nix/home-module.nix";
    };
  };
}
