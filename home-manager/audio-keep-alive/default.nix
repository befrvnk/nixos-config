{
  pkgs,
  lib,
  ...
}:
let
  # Script that plays silence to keep the audio amplifier active
  # This prevents pops when audio starts/stops by keeping the DAC powered on
  keepAliveScript = pkgs.writeShellScript "audio-keep-alive" ''
    export PATH="${
      lib.makeBinPath [
        pkgs.pulseaudio
        pkgs.coreutils
      ]
    }"

    # Wait for PipeWire to be ready
    sleep 3

    echo "Playing silence to default audio sink to prevent amplifier power cycling"

    # Play silence forever using pacat (PulseAudio compatible, works with PipeWire)
    # Reads raw zeros from /dev/zero, interprets as 48kHz stereo 16-bit audio
    # Volume set to 1% (0.01) which is inaudible but keeps the DAC active
    exec pacat --playback \
      --rate=48000 \
      --channels=2 \
      --format=s16le \
      --volume=655 \
      --latency-msec=1000 \
      /dev/zero
  '';
in
{
  # Systemd user service to keep audio device active
  # Prevents amplifier power cycling which causes pops
  systemd.user.services.audio-keep-alive = {
    Unit = {
      Description = "Keep audio amplifier active to prevent pops";
      After = [
        "pipewire.service"
        "wireplumber.service"
      ];
      Requires = [ "pipewire.service" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${keepAliveScript}";
      Restart = "always";
      RestartSec = "5";
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
