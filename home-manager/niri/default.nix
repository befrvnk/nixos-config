{ osConfig, pkgs, nix-colors, ... }:

{
  imports = [
    (import ./astal-shell.nix { inherit osConfig nix-colors; })
    (import ./config.nix { inherit pkgs; })
  ];
}
