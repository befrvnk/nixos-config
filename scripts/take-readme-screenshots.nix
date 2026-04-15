{ pkgs }:
pkgs.writeShellApplication {
  name = "take-readme-screenshots";
  runtimeInputs = with pkgs; [
    coreutils
    darkman
    fastfetch
    ghostty
    grim
    imagemagick
    niri
  ];
  text = builtins.readFile ./take-readme-screenshots.sh;
}
