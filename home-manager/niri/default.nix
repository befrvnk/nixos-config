{
  osConfig,
  pkgs,
  nix-colors,
  lib,
  ...
}:

{
  imports = [
    (import ./config.nix {
      inherit
        pkgs
        osConfig
        nix-colors
        lib
        ;
    })
  ];
}
