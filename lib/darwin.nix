{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
  overlayLib = import ./overlays.nix { inherit inputs; };
in
{
  mkDarwinHost =
    {
      hostname,
      system ? "aarch64-darwin",
      primaryUser ? "frank",
      homeDirectory ? "/Users/${primaryUser}",
    }:
    let
      hostPath = ../hosts/${hostname};
    in
    if !builtins.pathExists hostPath then
      throw "Unknown Darwin host: ${hostname} (expected ${toString hostPath})"
    else if !(lib.hasPrefix "/" homeDirectory) then
      throw "homeDirectory must be absolute for Darwin host ${hostname}: ${homeDirectory}"
    else
      inputs.nix-darwin.lib.darwinSystem {
        inherit system;
        specialArgs = {
          inherit inputs;
          hostDefaults = {
            inherit
              hostname
              system
              primaryUser
              homeDirectory
              ;
          };
        };
        modules = [
          # Apply darwin-compatible overlays
          { nixpkgs.overlays = overlayLib.darwinOverlays; }
          ./host-options-module.nix
          inputs.home-manager.darwinModules.home-manager
          hostPath
        ];
      };
}
