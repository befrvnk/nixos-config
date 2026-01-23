{
  inputs,
  ...
}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.frank = ../../home-manager/frank.nix;
    sharedModules = [
      inputs.niri.homeModules.niri
      inputs.stasis.homeModules.default
      inputs.stylix.homeModules.stylix
      inputs.vicinae.homeManagerModules.default
      ../../pkgs/hamr/hm-module.nix
    ];
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
