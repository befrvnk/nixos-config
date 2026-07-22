{ pkgs, ... }:

let
  homeCleanup = pkgs.callPackage ../../pkgs/home-cleanup/package.nix { };
in
{
  home.packages = [ homeCleanup ];
}
