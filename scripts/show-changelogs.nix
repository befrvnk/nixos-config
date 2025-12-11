# Wrapper script that injects dependencies for show-changelogs.sh
{ pkgs }:
pkgs.writeScript "show-changelogs" ''
  #!${pkgs.bash}/bin/bash
  # Inject tool paths
  nvd="${pkgs.nvd}/bin/nvd"
  nix="${pkgs.nix}/bin/nix"
  grep="${pkgs.gnugrep}/bin/grep"
  awk="${pkgs.gawk}/bin/awk"
  cut="${pkgs.coreutils}/bin/cut"
  sed="${pkgs.gnused}/bin/sed"

  ${builtins.readFile ./show-changelogs.sh}
''
