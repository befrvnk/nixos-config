{
  pkgs,
  inputs,
  ...
}:
{
  spawn-at-startup = [
    { command = [ "${pkgs.xwayland-satellite}/bin/xwayland-satellite" ]; }
    # Start awww daemon for wallpaper management with fade transitions
    {
      command = [
        "${inputs.awww.packages.${pkgs.system}.awww}/bin/awww-daemon"
      ];
    }
    # Initialize audio enhancement sink for volume control
    # The Framework audio enhancement filter-chain starts in an uninitialized state
    # where wpctl reports incorrect volume (1.0) and volume changes don't apply.
    # Running pw-loopback briefly activates the sink, after which volume control
    # works correctly even when the sink returns to suspended state.
    {
      command = [
        "${pkgs.bash}/bin/bash"
        "-c"
        "timeout 0.5 ${pkgs.pipewire}/bin/pw-loopback --capture-props='media.class=Audio/Sink' --playback-props='node.target=@DEFAULT_AUDIO_SINK@' || true"
      ];
    }
    # Initialize volume cache for ironbar (event-driven volume display)
    # This runs once at startup to populate the cache file that ironbar reads.
    # Subsequently, volume-ctl updates the cache whenever user changes volume.
    {
      command = [
        "volume-ctl"
        "init"
      ];
    }
  ];
}
