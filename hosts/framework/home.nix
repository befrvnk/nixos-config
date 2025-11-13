{
  stylix,
  vicinae,
  zen-browser,
  android-nixpkgs,
  niri,
  ...
}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.frank = ../../home-manager/frank.nix;
    sharedModules = [
      stylix.homeModules.stylix
      vicinae.homeManagerModules.default
      niri.homeModules.niri
    ];
    extraSpecialArgs = {
      inherit zen-browser;
      inherit android-nixpkgs;
    };
  };
}
