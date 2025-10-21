{ pkgs, inputs, ... }:

{
  imports =
    [
      ./hardware-configuration.nix
      ../../modules
      inputs.nixos-hardware.nixosModules.framework-amd-ai-300-series
    ];

  networking.hostName = "framework";
  environment.etc = {
    "1password/custom_allowed_browsers" = {
      text = ''
        .zen-wrapped
      '';
      mode = "0755";
    };
  };
}
