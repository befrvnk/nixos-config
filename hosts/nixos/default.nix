{ pkgs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules/system.nix
      ../../modules/gnome.nix
      ../../modules/pipewire.nix
      ../../modules/packages.nix
      ../../modules/users.nix
    ];
}
