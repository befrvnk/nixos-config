{ android-nixpkgs, niri, ... }:

{
  nixpkgs.overlays = [
    android-nixpkgs.overlays.default
    (import ../../overlays/niri.nix { inherit niri; })
  ];
}
