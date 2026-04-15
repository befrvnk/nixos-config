{ lib, pkgs, ... }:

let
  hmLib = import ../lib.nix { inherit lib pkgs; };

  # Script to pause/resume Spotify during suspend
  handleSpotifySuspendScript = hmLib.mkPathWrappedScript {
    name = "handle-spotify-suspend";
    packages = [
      pkgs.playerctl
      pkgs.systemd
      pkgs.coreutils
    ];
    script = ./handle-spotify-suspend.sh;
  };
in
{
  # Pause/resume Spotify during any suspend to prevent crashes
  # Spotify can crash when audio devices disconnect during suspend
  systemd.user.services.spotify-suspend-handler = hmLib.mkGraphicalUserService {
    description = "Pause/resume Spotify during suspend to prevent crashes";
    execStart = "${handleSpotifySuspendScript}";
  };
}
