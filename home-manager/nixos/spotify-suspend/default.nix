{ pkgs, ... }:

let
  # Script to pause/resume Spotify during suspend
  handleSpotifySuspendScript = pkgs.writeShellScript "handle-spotify-suspend" ''
    # Ensure required commands are in PATH
    export PATH="${pkgs.playerctl}/bin:${pkgs.systemd}/bin:${pkgs.coreutils}/bin:$PATH"

    ${builtins.readFile ./handle-spotify-suspend.sh}
  '';
in
{
  # Pause/resume Spotify during any suspend to prevent crashes
  # Spotify can crash when audio devices disconnect during suspend
  systemd.user.services.spotify-suspend-handler = {
    Unit = {
      Description = "Pause/resume Spotify during suspend to prevent crashes";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${handleSpotifySuspendScript}";
      Restart = "always";
      RestartSec = "5";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
