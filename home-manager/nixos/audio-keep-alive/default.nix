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
    ${builtins.readFile ./audio-keep-alive.sh}
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
