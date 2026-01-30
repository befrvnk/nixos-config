{ pkgs, ... }:

let
  alsaMixerInitScript = pkgs.writeShellScript "alsa-mixer-init" ''
    ${pkgs.alsa-utils}/bin/amixer -c1 sset Master 100%
    ${pkgs.alsa-utils}/bin/amixer -c1 sset PCM 100%
  '';
in
{
  services.pulseaudio.enable = false;

  # Set ALSA mixer levels to 100% at boot
  # Framework laptop defaults Master to 77% (-15 dB), leaving significant headroom unused
  # Card 1 is the HD-Audio Generic_1 (Family 17h/19h/1ah HD Audio Controller - speakers)
  systemd.services.alsa-mixer-init = {
    description = "Initialize ALSA mixer levels";
    after = [ "sound.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${alsaMixerInitScript}";
    };
  };
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Force 48kHz to eliminate pops from sample rate switching
    # All 44.1kHz sources (Spotify, QEMU) are resampled - inaudible quality difference
    extraConfig.pipewire = {
      "10-clock-config" = {
        "context.properties" = {
          "default.clock.rate" = 48000;
          "default.clock.allowed-rates" = [ 48000 ];
          # Quantum settings: balance latency vs stability
          # Lower = snappier response, higher = more stable
          # See: https://forum.endeavouros.com/t/pipewire-guide-audio-crackling-popping-and-latency/69602
          "default.clock.quantum" = 1024; # ~21ms at 48kHz (default: 1024)
          "default.clock.min-quantum" = 512; # ~11ms (allows lower latency apps)
          "default.clock.max-quantum" = 2048; # ~43ms (for demanding apps like QEMU)
          # Increase link buffers (default 16 causes crackling)
          "link.max-buffers" = 128;
        };
      };
    };

    # QEMU-specific latency via pulse.rules
    # QEMU requests ~2.7ms latency which causes underruns on most hardware
    # See: https://github.com/wwmm/easyeffects/issues/2406
    extraConfig.pipewire-pulse."99-qemu-latency" = {
      "pulse.rules" = [
        {
          matches = [ { "application.process.binary" = "qemu-system-x86_64"; } ];
          actions.update-props = {
            "pulse.min.req" = "4096/48000";
            "pulse.min.quantum" = "4096/48000";
          };
        }
      ];
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

      # Large ALSA buffer and headroom for stable playback
      # See: https://bbs.archlinux.org/viewtopic.php?id=280654
      alsa-buffer = {
        "monitor.alsa.rules" = [
          {
            # Match all ALSA output devices
            matches = [ { "node.name" = "~alsa_output.*"; } ];
            actions.update-props = {
              "api.alsa.period-size" = 1024;
              "api.alsa.headroom" = 8192;
              # Prevent node suspension to eliminate pops on pause/resume
              "session.suspend-timeout-seconds" = 0;
            };
          }
        ];
      };

      # Prevent suspension on all audio sinks and filter-chain nodes
      # This eliminates pops when audio starts/stops
      # Matches: convolver, filter-chain effects, and any Audio/Sink nodes
      audio-no-suspend = {
        "node.rules" = [
          {
            # Match filter-chain and audio effect nodes by name pattern
            matches = [
              { "node.name" = "~audio_effect.*"; }
              { "node.name" = "~filter-chain-*"; }
            ];
            actions.update-props = {
              "session.suspend-timeout-seconds" = 0;
            };
          }
          {
            # Match all Audio/Sink nodes by media.class
            matches = [
              { "media.class" = "Audio/Sink"; }
            ];
            actions.update-props = {
              "session.suspend-timeout-seconds" = 0;
            };
          }
        ];
      };

    };
  };
}
