{ android-nixpkgs, niri, ... }:

{
  # Host-specific overlays
  # Common overlays (like gemini-cli) are defined at the flake level
  nixpkgs.overlays = [
    android-nixpkgs.overlays.default
    niri.overlays.niri
  ];
}
