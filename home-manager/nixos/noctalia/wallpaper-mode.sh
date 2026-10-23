set -euo pipefail

# Native asynchronous hooks discard stdio; keep selection/errors in the journal.
log() {
  @coreutils@/bin/timeout 2s @util_linux@/bin/logger --tag noctalia-wallpaper-mode -- "$*" || true
}
fail() {
  printf '%s\n' "$*" >&2
  log "$*"
  exit 1
}
on_error() {
  local status=$?
  log "Wallpaper hook failed (exit $status)"
  exit "$status"
}
trap on_error ERR

# Hook children can overlap. Read current mode under the lock, not stale event env.
if [ -z "${XDG_RUNTIME_DIR:-}" ] || [ ! -d "$XDG_RUNTIME_DIR" ] || [ ! -O "$XDG_RUNTIME_DIR" ]; then
  fail 'Noctalia wallpaper hook requires an owned session runtime directory'
fi
exec 9>"$XDG_RUNTIME_DIR/noctalia-wallpaper-mode.lock"
@util_linux@/bin/flock -w 45 9
mode=$(@coreutils@/bin/timeout 10s @noctalia@ msg theme-mode-get)
case "$mode" in
  dark) wallpaper=@dark@ ;;
  light) wallpaper=@light@ ;;
  *) fail "Invalid resolved Noctalia mode: $mode" ;;
esac
reply=$(@coreutils@/bin/timeout 30s @noctalia@ msg wallpaper-set "$wallpaper")
if [ "$reply" != 'ok' ]; then
  fail "Native wallpaper selection failed: $reply"
fi
log "Selected $mode wallpaper via native hook"
