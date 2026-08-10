#!/usr/bin/env bash
# Diagnose "slow internet after suspend/resume" for the MediaTek MT7925 WiFi card.
#
# Runs twice around every sleep cycle:
#   wifi-wakeup-log.sh <interface> suspend   -> snapshot state just before suspending
#   wifi-wakeup-log.sh <interface> resume    -> snapshot state after resume (with short settle delay)
#
# Output goes to the unit journal (journalctl -u wifi-wakeup-log).
# Captured data helps distinguish three failure modes after wake:
#   1. Interface down / firmware did not re-probe        (ip link shows DOWN or missing)
#   2. PCIe link re-negotiated to a lower speed          (LnkCap/LnkSta in lspci)
#   3. WiFi power-save stuck on / weak signal            (iw power_save / iw link RSSI)
# Plus a gateway ping latency baseline for end-to-end reachability.

set -uo pipefail

WIFI_IF="${1:?usage: wifi-wakeup-log <interface> <suspend|resume>}"
ACTION="${2:?usage: wifi-wakeup-log <interface> <suspend|resume>}"

STATE_DIR="/var/lib/wifi-wakeup"
PRE_FILE="$STATE_DIR/pre-suspend.log"
POST_FILE="$STATE_DIR/post-resume.log"

mkdir -p "$STATE_DIR"

# Resolve the PCI BDF (bus:device.function) behind the netdev, if present.
# Missing interface itself is already diagnostic (module did not wake).
pci_bdf="$(
  readlink -f "/sys/class/net/${WIFI_IF}/device" 2>/dev/null \
    | xargs -r basename 2>/dev/null \
    || true
)"

snapshot() {
  {
    echo "=== wifi-wakeup $(date '+%F %T') uptime=$(awk '{print $1}' /proc/uptime) ==="
    echo "--- ip link show ${WIFI_IF} ---"
    ip link show "${WIFI_IF}" 2>&1 || echo "!! interface '${WIFI_IF}' missing (module did not wake?)"
    echo "--- iw dev ${WIFI_IF} get power_save ---"
    iw dev "${WIFI_IF}" get power_save 2>&1 || true
    echo "--- iw dev ${WIFI_IF} link (signal / rates) ---"
    iw dev "${WIFI_IF}" link 2>&1 || true
    if [[ -n "${pci_bdf}" ]]; then
      echo "--- PCIe ${pci_bdf} link capability / status / ASPM ---"
      lspci -s "${pci_bdf}" -vv 2>/dev/null | grep -Ei "LnkCap:|LnkSta:|ASPM " || echo "!! no PCIe link info for ${pci_bdf}"
    fi
    echo "--- default route ---"
    ip route show default 2>&1 || true
  }
}

case "$ACTION" in
  suspend)
    echo "### PRE-SUSPEND (captured just before sleep)"
    snapshot | tee "$PRE_FILE"
    ;;

  resume)
    echo "### POST-RESUME (captured ${SETTLE_DELAY:-5}s after wake to let link reassociate)"
    sleep "${SETTLE_DELAY:-5}"
    snapshot | tee "$POST_FILE"

    echo "--- diff: pre-suspend vs post-resume (ignoring timestamp header) ---"
    if [[ -f "$PRE_FILE" && -f "$POST_FILE" ]]; then
      diff \
        <(grep -v '^=== ' "$PRE_FILE") \
        <(grep -v '^=== ' "$POST_FILE") \
        || true
    else
      echo "!! pre-suspend snapshot missing (system may have been suspended before setup)"
    fi

    echo "--- gateway reachability / latency ---"
    if gw="$(ip route show default 2>/dev/null | awk '/^default/{print $3; exit}')" && [[ -n "$gw" ]]; then
      # Mitigate the 5s settle sleep default when validating manually.
      ping -c 3 -W 2 "$gw" 2>&1 || true
    else
      echo "!! no default gateway after resume"
    fi
    ;;
  *)
    echo "!! unknown action: $ACTION (expected suspend|resume)" >&2
    exit 1
    ;;
esac