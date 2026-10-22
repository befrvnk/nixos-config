{ pkgs, ... }:
let
  safeSuspend = import ../niri/safe-suspend-package.nix { inherit pkgs; };
in
{
  # Native logind/session-lock owns pre-sleep protection; native idle owns timings.
  # Keep the guarded power backend shared with the manual suspend shortcut.
  programs.noctalia.settings = {
    lockscreen = {
      enabled = true;
      lock_before_suspend = true;
      grace_period_seconds = 0;
      allow_empty_password = false;
      fingerprint = true;
      blurred_desktop = false;
      transition = [ ];
      wallpaper = "";
      monitors = [ ];
    };
    shell.session = {
      # Keep high-level inhibitors and lock confirmation for native power actions.
      power.suspend = "${safeSuspend}/bin/safe-suspend --require-lock";
      actions = [
        { action = "lock"; }
        { action = "logout"; }
        { action = "lock_and_suspend"; }
        { action = "reboot"; }
        { action = "shutdown"; }
      ];
    };
  };
}
