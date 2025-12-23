{
  # SCX sched_ext BPF scheduler
  # Uses scx_lavd for latency-aware scheduling with power efficiency features
  # Core Compaction: consolidates work onto fewer cores when utilization <50%,
  # allowing idle cores to enter deep C-states for power savings
  # See: https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
  };
}
