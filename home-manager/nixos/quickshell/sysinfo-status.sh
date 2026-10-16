#!/usr/bin/env bash
# Print CPU%, memory% and CPU temperature for the bar.
# Replaces ironbar's built-in sys_info type; output format:
#   "CPU% · MEM% · TEMP°C"
set -euo pipefail

# --- CPU usage: delta over two reads of /proc/stat --------------------------
read_cpu() {
  awk '/^cpu  / { for (i=2; i<=NF; i++) total += $i; idle = $5 } END { print total, idle }' /proc/stat
}

read -r T1 I1 < <(read_cpu)
sleep 0.4
read -r T2 I2 < <(read_cpu)
DT=$((T2 - T1)); DI=$((I2 - I1))
if [[ "$DT" -gt 0 ]]; then
  CPU=$(( (DT - DI) * 100 / DT ))
else
  CPU=0
fi

# --- Memory usage -------------------------------------------------------------
MEM_TOTAL=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
MEM_AVAIL=$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)
if [[ "$MEM_TOTAL" -gt 0 ]]; then
  MEM=$(( (MEM_TOTAL - MEM_AVAIL) * 100 / MEM_TOTAL ))
else
  MEM=0
fi

# --- CPU temperature ----------------------------------------------------------
# Pick the first thermal zone reporting a plausible CPU-ish temp (30..110°C).
TEMP="?"
for z in /sys/class/thermal/thermal_zone*/temp; do
  [[ -e "$z" ]] || continue
  read -r m < "$z" || continue
  if [[ "$m" =~ ^[0-9]+$ && "$m" -ge 30000 && "$m" -le 110000 ]]; then
    TEMP=$(( m / 1000 ))
    break
  fi
done

printf "%s%% %s%% %s°C\n" "$CPU" "$MEM" "$TEMP"