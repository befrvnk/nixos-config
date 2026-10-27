{ lib, pkgs, ... }:

let
  hmLib = import ../lib.nix { inherit lib pkgs; };

  lockOnSuspend = hmLib.mkPathWrappedScript {
    name = "1password-lock-on-suspend";
    packages = [
      pkgs.coreutils # stdbuf
      pkgs.glib # gdbus
      pkgs.systemd # busctl
    ];
    script = ./lock-on-suspend.sh;
  };
in
{
  # 1Password auto-lock is turned off so the app is unlocked once per session
  # (see docs/1password-ssh-session.md). Lock it at suspend so its SSH keys
  # are released before sleep and need another unlock after resume.
  systemd.user.services."1password-lock-on-suspend" = hmLib.mkGraphicalUserService {
    description = "Lock 1Password before system suspend";
    execStart = "${lockOnSuspend}";
  };
}
