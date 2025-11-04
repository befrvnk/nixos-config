{
  osConfig,
  pkgs,
  lib,
  ...
}:

{
  imports = [
    (import ./config.nix {
      inherit
        pkgs
        osConfig
        lib
        ;
    })
  ];
}
