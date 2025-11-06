{ stylix, dankMaterialShell, vicinae, zen-browser, android-nixpkgs, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.frank = import ../../home-manager/frank.nix;
    backupFileExtension = "backup";
    sharedModules = [
      stylix.homeModules.stylix
      dankMaterialShell.homeModules.dankMaterialShell.default
      vicinae.homeManagerModules.default
    ];
    extraSpecialArgs = {
      inherit zen-browser;
      inherit android-nixpkgs;
    };
  };
}
