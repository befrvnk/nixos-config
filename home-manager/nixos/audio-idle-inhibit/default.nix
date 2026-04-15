{ lib, pkgs, ... }:

let
  hmLib = import ../lib.nix { inherit lib pkgs; };
  audioIdleInhibitScript = hmLib.mkPathWrappedScript {
    name = "audio-idle-inhibit";
    packages = [
      pkgs.wireplumber
      pkgs.systemd
      pkgs.coreutils
      pkgs.gnugrep
    ];
    script = ./audio-idle-inhibit.sh;
  };
in
{
  # Prevent idle/suspend while audio is actually playing
  # Uses wpctl to detect actual audio activity (not just connected streams)
  # This solves the clamshell mode issue where browser streams stay "connected"
  systemd.user.services.audio-idle-inhibit = hmLib.mkGraphicalUserService {
    description = "Prevent idle/suspend when audio is playing";
    execStart = "${audioIdleInhibitScript}";
    restartSec = "10";
  };
}
