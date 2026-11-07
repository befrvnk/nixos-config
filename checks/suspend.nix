{ pkgs, ... }:
{
  safe-suspend =
    pkgs.runCommand "safe-suspend-tests"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.jq
        ];
      }
      ''
        ${pkgs.python3}/bin/python3 -B -m unittest discover \
          -s ${../home-manager/nixos/desktop-tools} -p 'test_safe_suspend.py'
        touch $out
      '';

}
