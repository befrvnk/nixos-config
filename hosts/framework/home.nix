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
    users.${hostConfig.primaryUser} = ../../home-manager/nixos/frank.nix;
    sharedModules = [
      inputs.stylix.homeModules.stylix
      inputs.vicinae.homeManagerModules.default
      inputs.niri.homeModules.niri

    ];
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
