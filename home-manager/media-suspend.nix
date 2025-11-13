{ pkgs, ... }:

let
  # Script to prevent auto-suspend while any media is playing
  # Works with YouTube, Spotify, VLC, and any MPRIS-compatible player
  # Does NOT prevent manual suspend (lid close)
  inhibitSuspendWhilePlaying = pkgs.writeShellScript "inhibit-suspend-while-playing" ''
    inhibitor_fd=""

    cleanup() {
      if [ -n "$inhibitor_fd" ]; then
        exec {inhibitor_fd}>&-
        inhibitor_fd=""
      fi
    }

    trap cleanup EXIT

    while true; do
      # Check if any media player is currently playing
      status=$(${pkgs.playerctl}/bin/playerctl status 2>/dev/null || echo "Stopped")

      if [ "$status" = "Playing" ]; then
        # Music is playing - acquire inhibitor lock if we don't have one
        if [ -z "$inhibitor_fd" ]; then
          exec {inhibitor_fd}<> <(${pkgs.systemd}/bin/systemd-inhibit \
            --what=idle \
            --who="Audio Playback" \
            --why="Music is playing" \
            --mode=block \
            sleep infinity 2>&1)
        fi
      else
        # Music stopped - release inhibitor lock
        cleanup
      fi

      sleep 5
    done
  '';

  # Script to pause/resume Spotify during suspend
  handleSpotifySuspendScript = pkgs.writeShellScript "handle-spotify-suspend" ''
    # Monitor suspend/resume events and pause/resume Spotify
    # This prevents audio device disconnection crashes during suspend

    ${pkgs.systemd}/bin/busctl monitor --user --match="interface=org.freedesktop.login1.Manager,member=PrepareForSleep" | \
    while read -r line; do
      if echo "$line" | grep -q "boolean true"; then
        # System is about to suspend
        status=$(${pkgs.playerctl}/bin/playerctl -p spotify status 2>/dev/null || echo "Stopped")
        if [ "$status" = "Playing" ]; then
          ${pkgs.playerctl}/bin/playerctl -p spotify pause 2>/dev/null || true
          echo "true" > /tmp/spotify-was-playing-$USER
        else
          rm -f /tmp/spotify-was-playing-$USER
        fi
      elif echo "$line" | grep -q "boolean false"; then
        # System resumed - wait for audio devices and resume if needed
        sleep 2
        if [ -f /tmp/spotify-was-playing-$USER ]; then
          ${pkgs.playerctl}/bin/playerctl -p spotify play 2>/dev/null || true
          rm -f /tmp/spotify-was-playing-$USER
        fi
      fi
    done
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
