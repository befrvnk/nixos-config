{ ... }:

{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Allow both 44.1kHz (Spotify, QEMU) and 48kHz (YouTube, system sounds)
    extraConfig.pipewire = {
      "10-clock-config" = {
        "context.properties" = {
          "default.clock.rate" = 44100;
          "default.clock.allowed-rates" = [
            44100
            48000
          ];
        };
      };
    };

    wireplumber.extraConfig = {
      # Disable UCM profiles to fix built-in microphone on Framework 13 AMD AI 300
      # UCM selects "Play HiFi quality Music" profile which disables DMIC
      # See: https://github.com/NixOS/nixos-hardware/issues/1603
      no-ucm = {
        "monitor.alsa.properties" = {
          "alsa.use-ucm" = false;
        };
      };

      # Increase ALSA buffer for all output devices to handle sample rate switches
      # Large headroom (8192) prevents crackling during 44.1kHz <-> 48kHz transitions
      # See: https://bbs.archlinux.org/viewtopic.php?id=280654
      alsa-buffer = {
        "monitor.alsa.rules" = [
          {
            # Match all ALSA output devices
            matches = [ { "node.name" = "~alsa_output.*"; } ];
            actions.update-props = {
              "api.alsa.period-size" = 1024;
              "api.alsa.headroom" = 8192;
            };
          }
        ];
      };

      # Increase buffer size for QEMU (Android emulator)
      # Prevents buffer underruns from emulator timing jitter
      qemu-latency = {
        "monitor.alsa.rules" = [
          {
            matches = [ { "application.process.binary" = "qemu-system-x86_64"; } ];
            actions.update-props = {
              "node.latency" = "4096/44100";
            };
          }
        ];
      };
    };
  };
}
