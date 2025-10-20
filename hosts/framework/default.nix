{ pkgs, inputs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules
      inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    ];

  networking.hostName = "framework";
}
