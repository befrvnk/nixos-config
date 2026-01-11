# Android Studio Setup

This guide covers the Android Studio configuration on NixOS with AMD GPU hardware acceleration for the Android emulator.

## Overview

Android Studio is configured in `home-manager/android/` with:

- **Android Studio Canary** - Latest development version
- **AMD GPU environment variables** - Required for hardware-accelerated emulation
- **`configure-avd` script** - Fixes AVD settings for AMD GPUs

## Configuration Files

```
home-manager/android/
├── default.nix           # Android Studio package and environment variables
├── configure-avd.sh      # AVD configuration script for AMD GPUs
└── update-vmoptions.sh   # Wayland native support fix
```

## AMD GPU Hardware Acceleration

The Android emulator requires specific environment variables to work with AMD GPUs. These are set via `systemd.user.sessionVariables` (not `home.sessionVariables`) to ensure GUI applications inherit them.

### Required Environment Variables

| Variable | Value | Purpose |
|----------|-------|---------|
| `VK_ICD_FILENAMES` | `/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json` | Points emulator to system Vulkan ICD |
| `RADV_DEBUG` | `zerovram` | Fixes gray screen on RDNA 3.5 GPUs |

### Why `systemd.user.sessionVariables`?

**Important**: `home.sessionVariables` creates a bash profile script that is NOT sourced by graphical sessions started via greetd. GUI applications like Android Studio won't receive those variables.

Using `systemd.user.sessionVariables` injects variables into the systemd user session, which all GUI applications inherit.

### Verifying Environment Variables

After rebuilding and logging back in:

```bash
# Check systemd user environment
systemctl --user show-environment | grep -E "VK_ICD|RADV"

# Check Android Studio process (while running)
cat /proc/$(pgrep -f "studio" | head -1)/environ | tr '\0' '\n' | grep -E "VK_ICD|RADV"
```

Expected output:
```
RADV_DEBUG=zerovram
VK_ICD_FILENAMES=/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json
```

## AVD Configuration

### The Problem

AVDs created in Android Studio use default settings that don't work reliably with AMD GPUs:

- `hw.gpu.mode=auto` - Doesn't select the correct GPU mode
- Quickboot enabled - Causes issues with hardware GPU mode
- Cold boot not forced - Leads to snapshot corruption

### The Solution: `configure-avd`

After creating an AVD in Android Studio, run `configure-avd` to fix the settings:

```bash
# Configure all AVDs
configure-avd

# Configure a specific AVD
configure-avd Pixel_9
```

### What `configure-avd` Does

1. **Sets `hw.gpu.mode=host`** - Forces hardware GPU acceleration
2. **Sets `fastboot.forceColdBoot=yes`** - Prevents snapshot issues
3. **Disables quickboot** - Required for hardware GPU mode

### Manual AVD Configuration

If you prefer to configure manually, edit `~/.android/avd/<AVD_NAME>.avd/config.ini`:

```ini
hw.gpu.enabled=yes
hw.gpu.mode=host
fastboot.forceColdBoot=yes
```

And create/edit `~/.android/avd/<AVD_NAME>.avd/quickbootChoice.ini`:

```ini
saveOnExit = false
```

## Creating a New AVD

1. **Open Android Studio** → Device Manager → Create Virtual Device
2. **Select device** (e.g., Pixel 9)
3. **Select system image** (e.g., API 36 with Google Play)
4. **Finish** the wizard with default settings
5. **Run `configure-avd`** to fix GPU settings:
   ```bash
   configure-avd
   ```
6. **Cold Boot** the emulator (not regular start):
   - In Device Manager, click the dropdown arrow next to Play button
   - Select "Cold Boot Now"

## Starting the Emulator

### From Android Studio

1. Open Device Manager
2. Click dropdown arrow next to your AVD
3. Select **"Cold Boot Now"** (important for first launch after configuration)

Subsequent launches can use normal start, but use Cold Boot if you experience issues.

### From Command Line

If you have the Android SDK in your PATH (e.g., from a devenv):

```bash
emulator -avd Pixel_9 -gpu host
```

## Troubleshooting

### Emulator Shows "Connecting to the Emulator" Forever

1. **Check environment variables** are set (see Verifying Environment Variables above)
2. **Run `configure-avd`** to fix AVD settings
3. **Use Cold Boot** instead of normal start
4. **Restart Android Studio** after rebuilding NixOS config

### Gray Screen in Emulator

The `RADV_DEBUG=zerovram` environment variable should fix this. If not:

1. Verify the variable is set in Android Studio's environment
2. Try Cold Boot
3. Check if the emulator is using hardware GPU:
   ```bash
   # In emulator's extended controls → Settings → Advanced
   # OpenGL ES renderer should show your GPU
   ```

### Emulator Crashes or Black Screen

1. **Delete AVD snapshots**:
   ```bash
   rm -rf ~/.android/avd/<AVD_NAME>.avd/snapshots
   ```
2. **Re-run `configure-avd`**
3. **Cold Boot** the emulator

### Environment Variables Not Applied

If variables aren't in Android Studio's environment:

1. **Log out and log back in** (required after NixOS rebuild)
2. **Start Android Studio fresh** (don't use a session from before the rebuild)
3. Verify with:
   ```bash
   systemctl --user show-environment | grep -E "VK_ICD|RADV"
   ```

### Audio Crackling When Emulator is Running

See [Android Emulator (QEMU) Audio](../CLAUDE.md#android-emulator-qemu-audio) in CLAUDE.md. The emulator requests very low audio latency which affects all system audio. This is addressed by PipeWire configuration in `modules/services/pipewire.nix`.

## Wayland Native Support

The `update-vmoptions.sh` script in `home-manager/android/` adds native Wayland support to fix blurry text issues. This is run separately when needed:

```bash
# Script adds -Dawt.toolkit.name=WLToolkit to Android Studio's vmoptions
~/nixos-config/home-manager/android/update-vmoptions.sh
```

## IntelliJ IDEA

IntelliJ IDEA is configured separately in `home-manager/intellij/`. It includes the NixIDEA plugin for Nix language support. The GPU environment variables are not needed for IntelliJ as it doesn't run Android emulators.

## Quick Reference

| Task | Command |
|------|---------|
| Configure all AVDs | `configure-avd` |
| Configure specific AVD | `configure-avd <name>` |
| Check env vars in systemd | `systemctl --user show-environment \| grep -E "VK_ICD\|RADV"` |
| List AVDs | `ls ~/.android/avd/` |
| Delete AVD snapshots | `rm -rf ~/.android/avd/<name>.avd/snapshots` |
| Cold boot from CLI | `emulator -avd <name> -gpu host -no-snapshot-load` |
