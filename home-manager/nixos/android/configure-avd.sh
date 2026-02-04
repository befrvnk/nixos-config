# shellcheck shell=bash
# Configure Android AVDs for AMD hardware GPU support
# Run this after creating an AVD in Android Studio
# Usage: configure-avd [AVD_NAME]
#   Without arguments, configures all AVDs

set -e
AVD_DIR="$HOME/.android/avd"

configure_avd() {
  local name="$1"
  local avd_path="$AVD_DIR/$name.avd"
  local config="$avd_path/config.ini"

  if [ ! -d "$avd_path" ]; then
    echo "Error: AVD '$name' not found at $avd_path"
    return 1
  fi

  echo "Configuring AVD: $name"

  # Enable GPU and set to host mode for hardware acceleration
  sed -i "s/^hw.gpu.enabled.*/hw.gpu.enabled=yes/" "$config"
  if grep -q "^hw.gpu.mode=" "$config"; then
    sed -i "s/^hw.gpu.mode=.*/hw.gpu.mode=host/" "$config"
  else
    echo "hw.gpu.mode=host" >> "$config"
  fi

  # Force cold boot (avoids snapshot issues with hardware GPU)
  if grep -q "^fastboot.forceColdBoot=" "$config"; then
    sed -i "s/^fastboot.forceColdBoot=.*/fastboot.forceColdBoot=yes/" "$config"
  else
    echo "fastboot.forceColdBoot=yes" >> "$config"
  fi

  # Disable quickboot (required for hardware GPU)
  echo "saveOnExit = false" > "$avd_path/quickbootChoice.ini"

  echo "  hw.gpu.mode=host"
  echo "  fastboot.forceColdBoot=yes"
  echo "  quickboot disabled"
}

if [ -n "$1" ]; then
  # Configure specific AVD
  configure_avd "$1"
else
  # Configure all AVDs
  if [ ! -d "$AVD_DIR" ]; then
    echo "No AVD directory found at $AVD_DIR"
    exit 1
  fi

  avds=$(find "$AVD_DIR" -maxdepth 1 -name "*.avd" -type d -exec basename {} .avd \;)
  if [ -z "$avds" ]; then
    echo "No AVDs found in $AVD_DIR"
    exit 1
  fi

  echo "Configuring all AVDs for AMD hardware GPU..."
  echo ""
  for avd in $avds; do
    configure_avd "$avd"
    echo ""
  done
fi

echo "Done. Restart Android Studio and use Cold Boot for the emulator."
