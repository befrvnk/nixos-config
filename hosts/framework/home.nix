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
      inputs.stylix.homeModules.stylix
      inputs.vicinae.homeManagerModules.default
      inputs.niri.homeModules.niri
      inputs.wayland-pipewire-idle-inhibit.homeModules.default
    ];
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
