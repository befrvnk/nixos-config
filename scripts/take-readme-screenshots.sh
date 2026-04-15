# shellcheck shell=bash
set -euo pipefail

SCREENSHOT_DIR="$HOME/nixos-config/screenshots"
THUMB_WIDTH=400
GHOSTTY_PID=""
ORIGINAL_MODE="$(darkman get 2>/dev/null || echo dark)"

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM

  echo ""
  echo "=== Cleaning up ==="

  niri msg action close-overview >/dev/null 2>&1 || true

  if [[ -n "$GHOSTTY_PID" ]]; then
    kill "$GHOSTTY_PID" 2>/dev/null || true
    wait "$GHOSTTY_PID" 2>/dev/null || true
  fi

  if [[ -n "$ORIGINAL_MODE" ]]; then
    echo "Restoring original mode: $ORIGINAL_MODE"
    darkman set "$ORIGINAL_MODE" >/dev/null 2>&1 || true
  fi

  exit "$exit_code"
}

trap cleanup EXIT INT TERM

echo "=== README Screenshot Automation ==="
echo "Output directory: $SCREENSHOT_DIR"
echo "Current mode: $ORIGINAL_MODE"

mkdir -p "$SCREENSHOT_DIR"

echo "Switching to workspace 1..."
niri msg action focus-workspace 1
sleep 0.5

echo "Launching Ghostty with fastfetch..."
ghostty -e sh -c 'fastfetch; exec nu' &
GHOSTTY_PID=$!
sleep 2

take_mode_screenshots() {
  local mode="$1"

  echo ""
  echo "=== Taking $mode mode screenshots ==="
  echo "Switching to $mode mode..."
  darkman set "$mode"

  echo "Waiting for theme to apply..."
  sleep 4

  niri msg action focus-workspace 1
  sleep 0.5

  echo "Taking desktop screenshot..."
  grim "$SCREENSHOT_DIR/desktop_$mode.png"

  echo "Opening overview mode..."
  niri msg action open-overview
  sleep 1

  echo "Taking overview screenshot..."
  grim "$SCREENSHOT_DIR/overview_$mode.png"

  echo "Closing overview mode..."
  niri msg action close-overview
  sleep 0.5
}

take_mode_screenshots light
take_mode_screenshots dark

echo ""
echo "=== Generating thumbnails ==="
for img in \
  "$SCREENSHOT_DIR/desktop_light.png" \
  "$SCREENSHOT_DIR/desktop_dark.png" \
  "$SCREENSHOT_DIR/overview_light.png" \
  "$SCREENSHOT_DIR/overview_dark.png"; do
  if [[ -f "$img" ]]; then
    thumb="${img%.png}_thumb.png"
    echo "Creating thumbnail: $(basename "$thumb")"
    convert "$img" -resize "$THUMB_WIDTH" "$thumb"
  fi
done

echo ""
echo "=== Done! ==="
echo "Screenshots saved to: $SCREENSHOT_DIR"
ls -la "$SCREENSHOT_DIR"
