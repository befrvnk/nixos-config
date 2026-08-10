{
  # SCX sched_ext BPF scheduler
  # Uses scx_flash (EDF scheduler with dynamic latency weighting) for interactive workloads
  # See: https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_flash/README.md
  #
  # flash assigns each task a latency weight that rises when it releases the CPU early,
  # so latency-sensitive tasks (editor, terminal, audio) stay responsive even when all
  # cores are saturated by CPU-bound workloads such as parallel builds.
  #
  # --primary-domain auto: Gate the initial dispatch domain based on the active platform
  #   power profile (read via tuned-ppd). On battery this favors the efficient cores and
  #   parks unused ones, giving the aggressive core-disabling we want for low idle power.
  #
  # --throttle-us: Periodically inject idle cycles to extend battery life on portable
  #   devices and reduce heat/fan noise. 0 = disabled; tuned value here is conservative.
  #
  # NOTE: We deliberately do NOT pass --cpufreq. flash's built-in frequency control needs
  # the schedutil governor, but this host uses amd_pstate=active where the CPU hardware
  # handles frequency autonomously via EPP. Leaving frequency control to EPP is the
  # better fit (also avoids needing a governor change).
  services.scx = {
    enable = true;
    scheduler = "scx_flash";
    extraArgs = [
      # `auto` is also flash's default, but being explicit documents the intent.
      "--primary-domain"
      "auto"
      # Match the low-wattage-on-battery goal that scx_lavd --autopower provided.
      "--throttle-us"
      "200"
    ];
  };

  # Reduce stop timeout to avoid long shutdown delays
  # Kernel falls back to CFS automatically if forcibly killed
  systemd.services.scx.serviceConfig.TimeoutStopSec = 10;
}
