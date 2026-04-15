{
  pkgs,
  lib,
  ...
}:
let
  hmLib = import ../lib.nix { inherit lib pkgs; };

  # Script that plays silence to keep the audio amplifier active
  # This prevents pops when audio starts/stops by keeping the DAC powered on
  keepAliveScript = hmLib.mkPathWrappedScript {
    name = "audio-keep-alive";
    packages = [
      pkgs.pulseaudio
      pkgs.coreutils
    ];
    script = ./audio-keep-alive.sh;
  };
in
{
  # Systemd user service to keep audio device active
  # Prevents amplifier power cycling which causes pops
  systemd.user.services.audio-keep-alive = hmLib.mkGraphicalUserService {
    description = "Keep audio amplifier active to prevent pops";
    execStart = "${keepAliveScript}";
    after = [
      "pipewire.service"
      "wireplumber.service"
    ];
    requires = [ "pipewire.service" ];
  };
}
