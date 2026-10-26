{
  # SCX sched_ext BPF scheduler
  # Uses scx_lavd (Latency-criticality Aware Virtual Deadline): every task gets a virtual
  # deadline derived from how latency-critical it has proven to be, so interactive tasks
  # (terminal, topbar, typing) are served quickly while parallel builds saturate the cores.
  # See: https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
  #
  # --autopilot: pick the power mode from *system load* instead of from the tuned power
  #   profile. While a build runs lavd shifts toward performance (responsive UI without
  #   having to switch profiles); at idle it drops to powersave with core compaction,
  #   which consolidates work and parks the unused cores - the battery behaviour we want.
  #   (`--autopower` would follow tuned-ppd instead, keeping powersave while loaded on
  #   framework-battery, i.e. exactly the lag this switch is meant to remove.)
  #
  # NOTE: lavd has no cpufreq control; frequency scaling stays with amd_pstate=active EPP
  #   as set by the tuned profile, so scheduler and power profile remain independent.
  #
  # Replaces scx_flash (EDF + latency weighting with profile-gated core domains), which
  # was swapped out after UI lag under sustained build load.
  services.scx = {
    enable = true;
    scheduler = "scx_lavd";
    extraArgs = [
      "--autopilot"
    ];
  };

  # Reduce stop timeout to avoid long shutdown delays
  # Kernel falls back to the built-in scheduler (EEVDF) automatically if forcibly killed
  systemd.services.scx.serviceConfig.TimeoutStopSec = 10;
}
