# Wrapper script that injects dependencies for take-readme-screenshots.sh
{ pkgs }:
pkgs.writeScript "take-readme-screenshots" ''
  #!${pkgs.bash}/bin/bash
  # Inject tool paths
  grim="${pkgs.grim}/bin/grim"
  convert="${pkgs.imagemagick}/bin/convert"
  mkdir="${pkgs.coreutils}/bin/mkdir"
  kill="${pkgs.coreutils}/bin/kill"
  sleep="${pkgs.coreutils}/bin/sleep"
  ls="${pkgs.coreutils}/bin/ls"

  ${builtins.readFile ./take-readme-screenshots.sh}
''
