{
  osConfig,
  pkgs,
  nix-colors,
  lib,
  ...
}:

{
  imports = [
    (import ./astal-shell.nix { inherit osConfig nix-colors; })
    (import ./config.nix { inherit pkgs osConfig nix-colors lib; })
  ];
}
