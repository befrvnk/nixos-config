# Automated screenshot capture for README
# This script is sourced by take-readme-screenshots.nix which injects dependencies
# Dependencies: $grim, $convert, $mkdir, $kill, $sleep, $ls

SCREENSHOT_DIR="$HOME/nixos-config/screenshots"
THUMB_WIDTH=400

echo "=== README Screenshot Automation ==="
echo "Output directory: $SCREENSHOT_DIR"

# Save current mode to restore later
ORIGINAL_MODE=$(darkman get)
echo "Current mode: $ORIGINAL_MODE"

# Ensure screenshot directory exists
"$mkdir" -p "$SCREENSHOT_DIR"

# Switch to workspace 1 for screenshots
echo "Switching to workspace 1..."
niri msg action focus-workspace 1
"$sleep" 0.5

# Launch ghostty with neofetch
echo "Launching Ghostty with neofetch..."
ghostty -e sh -c 'neofetch; exec zsh' &
GHOSTTY_PID=$!
"$sleep" 2  # Wait for window to appear and render

# Function to take screenshots for a mode
take_mode_screenshots() {
  local mode=$1
  echo ""
  echo "=== Taking $mode mode screenshots ==="

  # Switch to mode
  echo "Switching to $mode mode..."
  darkman set "$mode"

  # Wait for theme to fully apply (services restart, wallpaper change)
  echo "Waiting for theme to apply..."
  "$sleep" 4

  # Focus workspace 1 where ghostty is
  niri msg action focus-workspace 1
  "$sleep" 0.5

  # Take desktop screenshot
  echo "Taking desktop screenshot..."
  "$grim" "$SCREENSHOT_DIR/desktop_$mode.png"

  # Open overview mode
  echo "Opening overview mode..."
  niri msg action open-overview
  "$sleep" 1  # Wait for overview animation

  # Take overview screenshot
  echo "Taking overview screenshot..."
  "$grim" "$SCREENSHOT_DIR/overview_$mode.png"

  # Close overview mode
  echo "Closing overview mode..."
  niri msg action close-overview
  "$sleep" 0.5

  echo "Done with $mode mode"
}

# Take screenshots for both modes
take_mode_screenshots "light"
take_mode_screenshots "dark"

# Restore original mode
echo ""
echo "Restoring original mode: $ORIGINAL_MODE"
darkman set "$ORIGINAL_MODE"
"$sleep" 2

# Close the ghostty window
echo "Closing Ghostty..."
"$kill" $GHOSTTY_PID 2>/dev/null || true

# Generate thumbnails
echo ""
echo "=== Generating thumbnails ==="
for img in "$SCREENSHOT_DIR"/desktop_light.png "$SCREENSHOT_DIR"/desktop_dark.png \
           "$SCREENSHOT_DIR"/overview_light.png "$SCREENSHOT_DIR"/overview_dark.png; do
  if [[ -f "$img" ]]; then
    thumb="${img%.png}_thumb.png"
    echo "Creating thumbnail: $(basename "$thumb")"
    "$convert" "$img" -resize "$THUMB_WIDTH" "$thumb"
  fi
done

echo ""
echo "=== Done! ==="
echo "Screenshots saved to: $SCREENSHOT_DIR"
"$ls" -la "$SCREENSHOT_DIR"
