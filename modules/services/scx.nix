{
  # SCX sched_ext BPF scheduler
  # Uses scx_lavd (Latency-criticality Aware Virtual Deadline): every task gets a virtual
  # deadline derived from how latency-critical it has proven to be, so interactive tasks
  # (terminal, topbar, typing) are served quickly while parallel builds saturate the cores.
  # See: https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
  #
  # --autopower: take the power mode from the tuned/PPD profile. On battery,
  #   framework-battery/framework-powersave keep lavd in powersave with core
  #   compaction (unused cores park); on AC, framework-ac lets it use balanced.
  #   This keeps the mode under the bar's profile switch instead of letting system
  #   load override it (--autopilot would shift toward performance during a build
  #   even on battery).
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
      "--autopower"
    ];
  };

  # Reduce stop timeout to avoid long shutdown delays
  # Kernel falls back to the built-in scheduler (EEVDF) automatically if forcibly killed
  systemd.services.scx.serviceConfig.TimeoutStopSec = 10;
}
