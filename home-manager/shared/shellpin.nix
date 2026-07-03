{ inputs, pkgs, ... }:

{
  home.packages = [
    inputs.shellpin.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];
}
