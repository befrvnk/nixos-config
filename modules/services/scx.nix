{
  # SCX sched_ext BPF scheduler
  # Uses scx_rusty for work-conserving scheduling with load balancing
  # See: https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_rusty/README.md
  services.scx = {
    enable = true;
    scheduler = "scx_rusty";
  };
}
