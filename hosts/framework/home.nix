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

      # Home Manager uses the system pkgs set; keep Stylix from defining
      # Home Manager-local nixpkgs overlays that are ignored/deprecated with
      # useGlobalPkgs.
      { stylix.overlays.enable = false; }
    ];
    extraSpecialArgs = {
      inherit inputs hostConfig;
    };
  };
}
