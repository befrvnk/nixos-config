{
  stylix,
  dankMaterialShell,
  vicinae,
  zen-browser,
  android-nixpkgs,
  niri,
  opencode-flake,
  ...
}:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.frank = ../../home-manager/frank.nix;
    sharedModules = [
      stylix.homeModules.stylix
      dankMaterialShell.homeModules.dankMaterialShell.default
      vicinae.homeManagerModules.default
      niri.homeModules.niri
    ];
    extraSpecialArgs = {
      inherit zen-browser;
      inherit android-nixpkgs;
    };
  };
}
