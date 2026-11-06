{
  # SCX sched_ext BPF scheduler running through scx-loader
  # Uses scx_lavd (Latency-criticality Aware Virtual Deadline): every task gets a virtual
  # deadline derived from how latency-critical it has proven to be, so interactive tasks
  # (terminal, topbar, typing) are served quickly while parallel builds saturate the cores.
  # See: https://github.com/sched-ext/scx/blob/main/scheds/rust/scx_lavd/README.md
  #
  # services.scx (direct systemd service) was removed upstream in favor of the
  # D-Bus scx-loader daemon (NixOS 26.11, configure via /etc/scx_loader.toml). The
  # loader normally maps the power-profiles-daemon profile to one of its own modes
  # (Auto/Gaming/LowLatency/PowerSave/Server), whose bundled lavd defaults include
  # `--autopilot` - load-driven mode shifting, which we deliberately do not want.
  # Setting every mode to `--autopower` keeps the old behavior under every profile:
  # lavd takes the power mode from tuned/PPD directly. On battery, the tuned
  # framework-battery/framework-powersave profiles keep lavd in powersave with core
  # compaction (unused cores park); on AC, framework-ac lets it use balanced. The
  # bar's profile switch stays in charge; system load does not override it.
  #
  # NOTE: lavd has no cpufreq control; frequency scaling stays with amd_pstate=active EPP
  #   as set by the tuned profile, so scheduler and power profile remain independent.
  #
  # Replaces scx_flash (EDF + latency weighting with profile-gated core domains), which
  # was swapped out after UI lag under sustained build load.
  services.scx-loader = {
    enable = true;
    config = {
      default_sched = "scx_lavd";
      scheds = {
        scx_lavd = {
          auto_mode = [ "--autopower" ];
          gaming_mode = [ "--autopower" ];
          lowlatency_mode = [ "--autopower" ];
          powersave_mode = [ "--autopower" ];
          server_mode = [ "--autopower" ];
        };
      };
    };
  };

  # Reduce stop timeout to avoid long shutdown delays
  # Kernel falls back to the built-in scheduler (EEVDF) automatically if forcibly killed
  systemd.services.scx_loader.serviceConfig.TimeoutStopSec = 10;
}
