{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
  overlayLib = import ./overlays.nix { inherit inputs; };
in
{
  mkHost =
    {
      hostname,
      system ? "x86_64-linux",
      primaryUser ? "frank",
      homeDirectory ? "/home/${primaryUser}",
      # Host capability flags
      cpuVendor ? "intel", # "amd" or "intel"
      hasFingerprint ? false,
      hasTouchscreen ? false,
      enableAndroid ? false,
      enableLogitech ? false,
      enableNuphy ? false,
      wifiInterface ? null,
      abmPath ? null,
      platformProfilePath ? "/sys/firmware/acpi/platform_profile",
    }:
    let
      hostPath = ../hosts/${hostname};
      homeModulePath = ../hosts/${hostname}/home.nix;
    in
    if !builtins.pathExists hostPath then
      throw "Unknown NixOS host: ${hostname} (expected ${toString hostPath})"
    else if !builtins.pathExists homeModulePath then
      throw "Missing Home Manager module for host ${hostname}: ${toString homeModulePath}"
    else if
      !builtins.elem cpuVendor [
        "amd"
        "intel"
      ]
    then
      throw "Unsupported cpuVendor '${cpuVendor}' for host ${hostname}; expected one of: amd, intel"
    else if !(lib.hasPrefix "/" homeDirectory) then
      throw "homeDirectory must be absolute for host ${hostname}: ${homeDirectory}"
    else
      lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          hostDefaults = {
            inherit
              hostname
              system
              primaryUser
              homeDirectory
              cpuVendor
              hasFingerprint
              hasTouchscreen
              enableAndroid
              enableLogitech
              enableNuphy
              wifiInterface
              abmPath
              platformProfilePath
              ;
          };
        };
        modules = [
          # Apply common overlays
          { nixpkgs.overlays = overlayLib.nixosOverlays; }
          ./host-options-module.nix
          # Host-specific configuration (imports nixos-hardware, lanzaboote, etc.)
          hostPath
          homeModulePath
          # Common modules
          inputs.home-manager.nixosModules.home-manager
          inputs.stylix.nixosModules.stylix
        ];
      };
}
