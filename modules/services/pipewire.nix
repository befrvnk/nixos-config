{ ... }:

{
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

    # Disable UCM profiles to fix built-in microphone on Framework 13 AMD AI 300
    # UCM selects "Play HiFi quality Music" profile which disables DMIC
    # See: https://github.com/NixOS/nixos-hardware/issues/1603
    wireplumber.extraConfig.no-ucm = {
      "monitor.alsa.properties" = {
        "alsa.use-ucm" = false;
      };
    };
  };
}
