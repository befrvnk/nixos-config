#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
package_root="${1:-$repo_root/home-manager/shared/pi}"
pi_bin="${PI_BIN:-pi}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/pi-package-smoke.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/home" "$tmp_dir/agent"
cat >"$tmp_dir/assert-removed-tools.mjs" <<'EOF'
export default function assertRemovedTools(pi) {
  pi.on("session_start", () => {
    const removed = new Set(["explore", "explore_status"]);
    const registered = pi.getAllTools().filter((tool) => removed.has(tool.name));
    if (registered.length > 0) {
      throw new Error(`Removed tools are still registered: ${registered.map((tool) => tool.name).join(", ")}`);
    }
  });
}
EOF

export HOME="$tmp_dir/home"
export PI_CODING_AGENT_DIR="$tmp_dir/agent"
export PI_COPILOT_LIVE_MODELS=0
export PI_OFFLINE=1
export PI_SKIP_VERSION_CHECK=1

printf '%s\n' '{"type":"get_commands"}' |
  "$pi_bin" \
    --mode rpc \
    --no-session \
    --no-extensions \
    -e "$package_root" \
    -e "$tmp_dir/assert-removed-tools.mjs" \
    >"$tmp_dir/stdout" \
    2>"$tmp_dir/stderr"

if grep -q '"type":"extension_error"' "$tmp_dir/stdout" "$tmp_dir/stderr"; then
  cat "$tmp_dir/stderr" >&2
  cat "$tmp_dir/stdout" >&2
  echo "Pi reported an extension loading error." >&2
  exit 1
fi

for command in answer review subagent lsp-status lsp-restart lsp-stop lsp-log; do
  if ! grep -q "\"name\":\"$command\"" "$tmp_dir/stdout"; then
    cat "$tmp_dir/stderr" >&2
    cat "$tmp_dir/stdout" >&2
    echo "Pi package smoke test did not register command: $command" >&2
    exit 1
  fi
done

if grep -q '"name":"explore-fresh"' "$tmp_dir/stdout"; then
  cat "$tmp_dir/stdout" >&2
  echo "Pi package smoke test unexpectedly registered removed command: explore-fresh" >&2
  exit 1
fi

echo "Pi extension package loaded successfully."
