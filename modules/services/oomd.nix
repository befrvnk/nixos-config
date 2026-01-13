{
  # systemd-oomd configuration
  # Proactively kills processes under memory pressure before the kernel OOM killer
  # Works well with ZRAM (configured in core.nix) to prevent system freezes
  #
  # See: https://www.freedesktop.org/software/systemd/man/latest/systemd-oomd.service.html
  systemd.oomd = {
    enable = true;

    # Enable for user slices - important for desktop use
    # Monitors memory pressure in user sessions and kills misbehaving apps
    enableUserSlices = true;

    # Enable for system slice - covers system services
    enableSystemSlice = true;

    # Extra configuration options (oomd.conf)
    settings.OOM = {
      # How long memory pressure must exceed the limit before action (Fedora default: 20s)
      # Lower values react faster but may kill processes during temporary spikes
      DefaultMemoryPressureDurationSec = "20s";

      # Swap usage threshold before oomd intervenes
      # With ZRAM at high swappiness (180), set this reasonably high
      SwapUsedLimit = "90%";
    };
  };
}
