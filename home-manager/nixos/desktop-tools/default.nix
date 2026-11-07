{
  config,
  lib,
  pkgs,
  ...
}:
let
  safeSuspend = import ./safe-suspend-package.nix { inherit pkgs; };
in
{
  home.packages = [
    pkgs.playerctl
    pkgs.wireplumber
    pkgs.brightnessctl
    pkgs.pavucontrol

    # Query structured logind data; idle/lid-only locks do not veto manual sleep.
    safeSuspend

    # Toggle ABM (Adaptive Backlight Management) for photo editing mode
    # ABM trades color accuracy for power savings
    (pkgs.writeShellScriptBin "toggle-abm" ''
      export PATH="${pkgs.libnotify}/bin:$PATH"
      ${builtins.readFile ./toggle-abm.sh}
    '')

    # Unified brightness control for internal + external monitors
    # Internal: brightnessctl (synchronous) + native display-only Noctalia OSD
    # External: syncs to internal brightness, catching up at its own pace
    (pkgs.writeShellScriptBin "brightness-ctl" ''
      export PATH="${
        lib.makeBinPath [
          pkgs.brightnessctl
          pkgs.coreutils
          pkgs.ddcutil
          pkgs.gawk
          config.programs.noctalia.package
        ]
      }"
      ${builtins.readFile ./brightness-ctl.sh}
    '')
  ];
}
