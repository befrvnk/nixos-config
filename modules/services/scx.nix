{
  # SCX sched_ext BPF scheduler
  # Uses scx_lavd (Latency-criticality Aware Virtual Deadline) for interactive workloads
  # See: https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
  #
  # --autopower: Automatically switches between power modes (powersave/balanced/performance)
  # based on system's Energy Performance Preference (EPP) and CPU utilization.
  # Requires amd_pstate=active kernel parameter to read EPP.
  #
  # Core Compaction: When CPU usage < 50%, active cores run at higher frequencies
  # while idle cores stay in C-State sleep for better power efficiency.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
    extraArgs = [ "--autopower" ];
  };

  # Reduce stop timeout to avoid long shutdown delays
  # Kernel falls back to CFS automatically if forcibly killed
  systemd.services.scx.serviceConfig.TimeoutStopSec = 10;
}
