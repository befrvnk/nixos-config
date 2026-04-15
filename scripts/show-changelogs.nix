{ pkgs }:
pkgs.writeShellApplication {
  name = "show-changelogs";
  runtimeInputs = with pkgs; [
    coreutils
    gawk
    gnugrep
    gnused
    nix
    nvd
  ];
  text = builtins.readFile ./show-changelogs.sh;
}
