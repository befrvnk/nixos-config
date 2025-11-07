{ android-nixpkgs, niri, ... }:

{
  nixpkgs.overlays = [
    android-nixpkgs.overlays.default
    niri.overlays.niri
    (import ../../overlays/gemini-cli.nix)
  ];
}
