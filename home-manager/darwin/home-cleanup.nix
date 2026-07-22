{ pkgs, ... }:

let
  homeCleanup = pkgs.writeShellApplication {
    name = "home-cleanup";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.git
    ];
    text = builtins.readFile ./home-cleanup.sh;
  };
in
{
  home.packages = [ homeCleanup ];
}
