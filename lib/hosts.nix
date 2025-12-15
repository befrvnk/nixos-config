{ inputs }:
let
  inherit (inputs.nixpkgs) lib;

  # Common overlays applied to all hosts
  commonOverlays = [
    inputs.android-nixpkgs.overlays.default
    inputs.niri.overlays.niri
    (import ../overlays/niri.nix)
    inputs.claude-code.overlays.default
    (import ../overlays/claude-code.nix)
    (import ../overlays/user-scanner.nix)
  ];
in
{
  mkHost =
    {
      hostname,
      system ? "x86_64-linux",
      # Host capability flags
      cpuVendor ? "intel", # "amd" or "intel"
      hasFingerprint ? false,
      hasTouchscreen ? false,
    }:
    lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        hostConfig = {
          inherit
            hostname
            cpuVendor
            hasFingerprint
            hasTouchscreen
            ;
        };
      };
      modules = [
        # Apply common overlays
        { nixpkgs.overlays = commonOverlays; }
        # Host-specific configuration (imports nixos-hardware, lanzaboote, etc.)
        ../hosts/${hostname}
        ../hosts/${hostname}/home.nix
        # Common modules
        inputs.home-manager.nixosModules.home-manager
        inputs.stylix.nixosModules.stylix
      ];
    };
}
