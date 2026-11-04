#!/usr/bin/env bash
# Summarize falcon-observer session summaries. The observer's output directory is
# root-only, so run this script with sudo.
set -euo pipefail

source_dir="/var/log/falcon-observer"
output=""

usage() {
  cat <<'EOF'
usage: falcon-report.sh [--source DIR] [--output FILE]

  --source DIR   falcon-observer output directory (default /var/log/falcon-observer)
  --output FILE  write the report to FILE with mode 0644 instead of stdout
EOF
}

while (($#)); do
  case $1 in
    --source)
      [[ $# -ge 2 ]] || { echo "error: --source needs a directory" >&2; exit 2; }
      source_dir=$2
      shift 2
      ;;
    --output)
      [[ $# -ge 2 ]] || { echo "error: --output needs a file" >&2; exit 2; }
      output=$2
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

cores=0
if command -v sysctl >/dev/null 2>&1; then
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 0)
fi
case $cores in
  '' | *[!0-9]*) cores=0 ;;
esac

if [[ ! -d "$source_dir" || ! -r "$source_dir" || ! -x "$source_dir" ]]; then
  echo "error: cannot read $source_dir (run with sudo)" >&2
  exit 1
fi

summaries=()
while IFS= read -r file; do
  if jq empty "$file" >/dev/null 2>&1; then
    summaries+=("$file")
  else
    echo "warning: skipping unreadable summary $file" >&2
  fi
done < <(find "$source_dir" -mindepth 2 -maxdepth 2 -name summary.json -type f -print | sort)

if ((${#summaries[@]} == 0)); then
  echo "No completed falcon-observer sessions in $source_dir" >&2
  exit 1
fi

write_report() {
  jq -s -r --argjson cores "$cores" -f /dev/stdin "${summaries[@]}" <<'JQ'
def f1: ((. * 10 | round) / 10) | tostring;
def f2: ((. * 100 | round) / 100) | tostring;
def gib: . / 1073741824 | f2;
def mib: . / 1048576 | f2;
def median:
  sort as $s
  | ($s | length) as $n
  | if $n == 0 then null
    elif ($n % 2) == 1 then $s[($n / 2 | floor)]
    else (($s[$n / 2 - 1] + $s[$n / 2]) / 2)
    end;
def mean: if length == 0 then null else add / length end;
def wmean(value; weight):
  map({v: value, w: weight})
  | map(select(.v != null and .w != null))
  | (map(.w) | add // 0) as $total
  | if $total == 0 then null else (map(.v * .w) | add) / $total end;
def num: if . == null then "-" else f2 end;
def text: if . == null or . == "" then "-" else . end;
def join_nonempty: map(select(. != null and . != "")) | join(" ");

def duration: ((.baseline.duration_seconds // 0) + (.build.duration_seconds // 0));

[ .[]
  | {
      started_at: (.started_at // ""),
      project: .project,
      build_system: .build_system,
      duration_s: duration,
      baseline_s: (.baseline.duration_seconds // 0),
      build_s: (.build.duration_seconds // 0),
      build_cpu: .build.build_cpu_percent.mean,
      build_cpu_p95: .build.build_cpu_percent.p95,
      system_cpu: .build.system_cpu_percent.mean,
      system_cpu_p95: .build.system_cpu_percent.p95,
      falcon_build_cpu_s: .build.falcon_delta.cpu_seconds,
      cpu_base: .baseline.falcon_cpu_percent.mean,
      cpu_build: .build.falcon_cpu_percent.mean,
      cpu_base_samples: .baseline.falcon_cpu_percent.samples,
      cpu_build_samples: .build.falcon_cpu_percent.samples,
      cpu_base_p95: .baseline.falcon_cpu_percent.p95,
      cpu_build_p95: .build.falcon_cpu_percent.p95,
      cpu_build_max: .build.falcon_cpu_percent.maximum,
      cpu_mult: .falcon_cpu_multiplier,
      read_mult: .falcon_read_multiplier,
      cpu_s: (((.baseline.falcon_delta.cpu_seconds // 0) + (.build.falcon_delta.cpu_seconds // 0))),
      baseline_cpu_s: (.baseline.falcon_delta.cpu_seconds // 0),
      build_cpu_s: (.build.falcon_delta.cpu_seconds // 0),
      read_b: (((.baseline.falcon_delta.read_bytes // 0) + (.build.falcon_delta.read_bytes // 0))),
      baseline_read_b: (.baseline.falcon_delta.read_bytes // 0),
      build_read_bytes: (.build.falcon_delta.read_bytes // 0),
      written_b: (((.baseline.falcon_delta.written_bytes // 0) + (.build.falcon_delta.written_bytes // 0))),
      max_compressed: ([.baseline.maximum_compressed_bytes, .build.maximum_compressed_bytes] | map(select(. != null)) | max // 0),
      max_swap: ([.baseline.maximum_swap_bytes, .build.maximum_swap_bytes] | map(select(. != null)) | max // 0),
      queue: (.falcon_stats_delta.queue_processed // 0),
      cache_hits: (.falcon_stats_delta.cache_read_hits // 0),
      cache_misses: (.falcon_stats_delta.cache_read_misses // 0),
      auth_exec: (.falcon_stats_delta.endpoint_security_auth_exec // 0),
      static_requests: (.falcon_stats_delta.static_analysis_requests // 0),
      static_too_large: (.falcon_stats_delta.static_analysis_too_large // 0),
      events_sent: (.falcon_stats_delta.events_sent_rolling_1h_net // 0),
      pm_samples: (.powermetrics.falcon.samples // 0),
      pm_cpu: .powermetrics.falcon.mean_cpu_percent,
      pm_cpu_p95: .powermetrics.falcon.p95_cpu_percent,
      pm_cpu_max: .powermetrics.falcon.maximum_cpu_percent,
      pm_read: .powermetrics.falcon.mean_read_bytes_per_second,
      pm_energy: .powermetrics.falcon.mean_energy_impact,
      deep_trace: (.collectors.deep_trace // false),
      falcon_sampled: (.collectors.falcon_sampled // false),
      pm_truncated: (.collectors.powermetrics_truncated // false),
      fs_truncated: (.collectors.fs_usage_truncated // false),
      raw_retained: (.raw_data_retained // false),
      errors_seen: (.collector_errors_seen // false),
      stop_reason: .stop_reason,
      fs_lines: (.file_activity.falcon_lines // null),
      path_events: (.file_activity.path_events // 0)
    }
] as $sessions

| [ $sessions[] | select(.cpu_base != null and .cpu_build != null) ] as $cpu_pairs
| ($cpu_pairs | wmean(.cpu_base; .cpu_base_samples)) as $base_cpu
| ($cpu_pairs | wmean(.cpu_build; .cpu_build_samples)) as $build_cpu
| [ $sessions[] | .cpu_mult | select(. != null and . > 0) ] as $mults
| [ $sessions[].pm_cpu | select(. != null) ] as $pm_cpus
| ([ $sessions[] | select(.pm_cpu != null) | .pm_samples ] | add // 0) as $pm_samples
| ([ $sessions[] | select(.pm_cpu != null) | .pm_cpu * .pm_samples ] | add // 0) as $pm_weighted
| ([ $sessions[].cache_hits ] | add // 0) as $cache_hits
| ([ $sessions[].cache_misses ] | add // 0) as $cache_misses
| ([ $sessions[].duration_s ] | add // 0) as $total_s
| ([ $sessions[].build_s ] | add // 0) as $total_build_s
| ([ $sessions[].baseline_s ] | add // 0) as $total_baseline_s
| ([ $sessions[].read_b ] | add // 0) as $total_read_b
| ([ $sessions[].written_b ] | add // 0) as $total_written_b
| ([ $sessions[].cpu_s ] | add // 0) as $total_cpu_s
| ([ $sessions[].build_cpu_s ] | add // 0) as $total_build_cpu_s
| ([ $sessions[].queue ] | add // 0) as $queue
| ([ $sessions[].auth_exec ] | add // 0) as $auth_exec
| ([ $sessions[].static_requests ] | add // 0) as $static_requests
| ([ $sessions[].static_too_large ] | add // 0) as $static_too_large
| ([ $sessions[].events_sent ] | add // 0) as $events_sent
| ([ $sessions[].max_compressed ] | max // 0) as $max_compressed
| ([ $sessions[].max_swap ] | max // 0) as $max_swap
| ([ $sessions[] | select(.errors_seen) ] | length) as $error_sessions
| ([ $sessions[] | select(.raw_retained) ] | length) as $raw_sessions
| ([ $sessions[] | select(.deep_trace) ] | length) as $deep_sessions
| ([ $sessions[] | select(.falcon_sampled) ] | length) as $sampled_sessions
| ([ $sessions[] | select(.pm_truncated) ] | length) as $pm_truncated_sessions
| ([ $sessions[] | select(.fs_truncated) ] | length) as $fs_truncated_sessions
| ([ $sessions[].project | select(. != null and . != "") ] | unique) as $projects
| ([ $sessions[].build_system | select(. != null and . != "") ] | unique) as $build_systems

| "# Falcon observer report",
  "",
  "- Sessions: \($sessions | length) across \($projects | length) project(s): \(if ($projects | length) == 0 then "-" else ($projects | join(", ")) end)",
  "- Build systems: \(if ($build_systems | length) == 0 then "-" else ($build_systems | join(", ")) end)",
  "- First session: \($sessions[0].started_at | if length >= 16 then .[0:16] | gsub("T"; " ") else text end)",
  "- Last session: \($sessions[-1].started_at | if length >= 16 then .[0:16] | gsub("T"; " ") else text end)",
  "- Timestamps use the observer's local timezone.",
  "- Machine cores: \(if $cores > 0 then $cores else "unknown" end)",
  "",
  "## Totals",
  "",
  "| Metric | Value |",
  "| --- | ---: |",
  "| Observed session time | \(($total_s / 60) | f2) min (\(($total_build_s / 60) | f2) min build, \(($total_baseline_s / 60) | f2) min baseline) |",
  "| Falcon CPU time | \($total_cpu_s | f2) s (\($total_build_cpu_s | f2) s during builds) |",
  "| Falcon physical I/O | \($total_read_b | gib) GiB read, \($total_written_b | gib) GiB written |",
  "| Falcon CPU multiplier | \(if ($mults | length) == 0 then "-" else "median \(($mults | median) | f2)x, mean \(($mults | mean) | f2)x, range \($mults | min | f2)x-\($mults | max | f2)x over \($mults | length) session(s) with a baseline" end) |",
  "| Falcon CPU during builds | baseline mean \(($base_cpu // ([ $cpu_pairs[].cpu_base ] | mean)) | num)%, build mean \(($build_cpu // ([ $cpu_pairs[].cpu_build ] | mean)) | num)%, build p95 (session avg) \(([ $sessions[].cpu_build_p95 | select(. != null) ] | mean) | num)%, build max \(([ $sessions[].cpu_build_max | select(. != null) ] | max) | num)% |",
  "| Powermetrics Falcon CPU | weighted mean \(if $pm_samples == 0 then "-" else ($pm_weighted / $pm_samples) | f2 end)%, mean p95 \(([ $sessions[].pm_cpu_p95 | select(. != null) ] | mean) | num)%, peak \(([ $sessions[].pm_cpu_max | select(. != null) ] | max) | num)% |",
  "| Powermetrics Falcon read rate | mean \(([ $sessions[].pm_read | select(. != null) ] | mean) / 1048576 | f2) MiB/s |",
  "| Powermetrics Falcon energy impact | mean \(([ $sessions[].pm_energy | select(. != null) ] | mean) | f2) |",
  "| Falcon queue | \($queue) entries processed |",
  "| Falcon sensor cache | \($cache_hits) hits / \($cache_misses) misses (\(if ($cache_hits + $cache_misses) == 0 then "-" else (($cache_hits * 100) / ($cache_hits + $cache_misses) | f1) end)% hit rate) |",
  "| Endpoint Security exec authorizations | \($auth_exec) |",
  "| Static analysis requests | \($static_requests) (\($static_too_large) too large) |",
  "| Rolling one-hour event net | \($events_sent) |",
  "| Peak memory pressure | \($max_compressed | gib) GiB compressed, \($max_swap | gib) GiB swap |",
  "",
  "## Diagnostics",
  "",
  "| Metric | Sessions |",
  "| --- | ---: |",
  "| Collector errors | \($error_sessions) |",
  "| Raw data retained | \($raw_sessions) |",
  "| Deep traces | \($deep_sessions) |",
  "| Falcon stack samples | \($sampled_sessions) |",
  "| Powermetrics truncated | \($pm_truncated_sessions) |",
  "| fs_usage truncated | \($fs_truncated_sessions) |",
  "",
  "## Build capacity",
  "",
  "| Started | Build min | Build CPU (cores, mean / p95) | System CPU (%, mean / p95) | Falcon CPU s (build) | Falcon share of busy CPU (%) | CPU-bound upper bound |",
  "| --- | ---: | ---: | ---: | ---: | ---: | ---: |",
  ( $sessions[]
    | "| \(.started_at | if length >= 16 then .[0:16] | gsub("T"; " ") else text end)"
      + " | \(.build_s / 60 | f1)"
      + " | \(if .build_cpu == null then "-" else "\(.build_cpu / 100 | f2) / \(if .build_cpu_p95 == null then "-" else (.build_cpu_p95 / 100 | f2) end)" end)"
      + " | \(.system_cpu | num) / \(.system_cpu_p95 | num)"
      + " | \(if .falcon_build_cpu_s == null then "-" else (.falcon_build_cpu_s | f1) end)"
      + " | \(if $cores > 0 and .system_cpu != null and .system_cpu > 0 and .falcon_build_cpu_s != null and .build_s > 0 then (.falcon_build_cpu_s / (.system_cpu / 100 * $cores * .build_s) * 100 | f1) else "-" end)"
      + " | \(if $cores > 0 and .falcon_build_cpu_s != null then (.falcon_build_cpu_s / $cores | f1) else "-" end) s"
      + " (\(if $cores > 0 and .falcon_build_cpu_s != null and .build_s > 0 then (.falcon_build_cpu_s / $cores / .build_s * 100 | f1) else "-" end)%) |"
  ),
  "",
  "Build CPU and system CPU are phase means; system CPU is a share of all cores.",
  "The upper bound assumes a fully CPU-bound build and spreads Falcon's CPU time over every core.",
  "",
  "## Per session",
  "",
  "| Started (local) | Project | Build | Build min | Base min | Falcon CPU % base->build | CPU x | Falcon CPU s | Falcon read MiB base->build | PM p95 % | Flags |",
  "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
  ( $sessions[]
    | "| \(.started_at | if length >= 16 then .[0:16] | gsub("T"; " ") else . end)"
      + " | \(.project | text)"
      + " | \(.build_system | text)"
      + " | \(.build_s / 60 | f1)"
      + " | \(.baseline_s / 60 | f1)"
      + " | \(.cpu_base | num) -> \(.cpu_build | num)"
      + " | \(.cpu_mult | if . == null then "-" else "\(f2)x" end)"
      + " | \(.cpu_s | f2)"
      + " | \(.baseline_read_b | mib) -> \(.build_read_bytes | mib)"
      + " | \(.pm_cpu_p95 | num)"
      + " | \([if .errors_seen then "errors" else null end, if .raw_retained then "raw" else null end, if .deep_trace then "deep" else null end, if .falcon_sampled then "sampled" else null end, if .pm_truncated or .fs_truncated then "truncated" else null end] | join_nonempty | text) |"
  )
JQ
}

if [[ -z "$output" ]]; then
  write_report
else
  output_dir=$(dirname "$output")
  if [[ ! -d "$output_dir" ]]; then
    echo "error: output directory does not exist: $output_dir" >&2
    exit 1
  fi
  temp_file=$(mktemp "${output}.XXXXXX")
  trap 'rm -f "$temp_file"' EXIT
  write_report >"$temp_file"
  chmod 0644 "$temp_file"
  if [[ -n "${SUDO_UID:-}" && -n "${SUDO_GID:-}" ]]; then
    chown "$SUDO_UID:$SUDO_GID" "$temp_file" 2>/dev/null || true
  fi
  mv "$temp_file" "$output"
  trap - EXIT
  echo "Report written to $output"
fi
