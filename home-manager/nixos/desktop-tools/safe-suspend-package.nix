{ pkgs }:
pkgs.writeShellScriptBin "safe-suspend" ''
  export PATH="${
    pkgs.lib.makeBinPath [
      pkgs.jq
      pkgs.libnotify
      pkgs.systemd
    ]
  }"
  ${builtins.readFile ./safe-suspend.sh}
''
