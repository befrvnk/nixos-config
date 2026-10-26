{ inputs, system }:
let
  inherit (inputs.nixpkgs) lib;
  overlayLib = import ../lib/overlays.nix { inherit inputs; };
  pkgs = import inputs.nixpkgs {
    inherit system;
    config.allowUnfree = true;
    overlays =
      if lib.hasSuffix "darwin" system then overlayLib.darwinOverlays else overlayLib.nixosOverlays;
  };
  args = {
    inherit
      inputs
      lib
      pkgs
      system
      ;
  };
in
(import ./cache.nix args)
// (import ./packages.nix args)
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux (
  (import ./kernel.nix args)
  // (import ./umbriel.nix args)
  // (import ./noctalia.nix args)
  // (import ./suspend.nix args)
)
// lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin (import ./darwin.nix args)
