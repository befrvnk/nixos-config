{ pkgs, ... }:

let
  # Script to prevent auto-suspend while any media is playing
  inhibitSuspendWhilePlaying = pkgs.writeShellScript "inhibit-suspend-while-playing" ''
    # Ensure required commands are in PATH
    export PATH="${pkgs.playerctl}/bin:${pkgs.systemd}/bin:${pkgs.coreutils}/bin:$PATH"

    ${builtins.readFile ./inhibit-suspend-while-playing.sh}
  '';

  # Script to pause/resume Spotify during suspend
  handleSpotifySuspendScript = pkgs.writeShellScript "handle-spotify-suspend" ''
    # Ensure required commands are in PATH
    export PATH="${pkgs.playerctl}/bin:${pkgs.systemd}/bin:${pkgs.coreutils}/bin:$PATH"

    ${builtins.readFile ./handle-spotify-suspend.sh}
  '';
in
{
  # Prevent auto-suspend while any media is playing
  # Works with YouTube, Spotify, VLC, and any MPRIS-compatible player
  # This does NOT prevent lid-close suspend
  systemd.user.services.inhibit-suspend-while-playing = {
    Unit = {
      Description = "Prevent auto-suspend when media is playing";
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${inhibitSuspendWhilePlaying}";
      Restart = "always";
      RestartSec = "10";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };

  # Pause/resume Spotify during any suspend to prevent crashes
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
