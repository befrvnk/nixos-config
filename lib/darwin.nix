{ inputs }:
let
  inherit (inputs.nixpkgs) lib;
in
{
  mkDarwinHost =
    {
      hostname,
      system ? "aarch64-darwin",
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
      };
      modules = [
        ../hosts/${hostname}
      ];
    };
}
