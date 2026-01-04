{ ... }:

{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Allow 44.1kHz for QEMU/Android emulator compatibility
    # QEMU outputs at 44100Hz - allowing it avoids resampling overhead
    extraConfig.pipewire = {
      "10-clock-config" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
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

      # Increase buffer size specifically for QEMU (Android emulator)
      # Prevents buffer underruns from emulator timing jitter without
      # adding latency to other applications like Spotify/YouTube
      qemu-latency = {
        "monitor.alsa.rules" = [
          {
            matches = [ { "application.process.binary" = "qemu-system-x86_64"; } ];
            actions = {
              update-props = {
                "node.latency" = "4096/48000";
              };
            };
          }
        ];
      };
    };
  };
}
