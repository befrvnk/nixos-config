# External Monitor Brightness Control

## Issue

The brightness control slider in DankMaterialShell (DMS) control panel does not work with external monitors. The slider only controls the Framework 13 laptop's built-in display, not the external 4K monitor connected via USB-C.

## Investigation Summary

### Current Configuration

**Display Setup:**
- Built-in display: `eDP-1` (Framework 13 laptop screen)
- External monitor: `DP-3` (4K monitor via USB-C)
- Configuration: `home-manager/niri/outputs.nix`

**Brightness Control Setup:**
- DMS brightness control enabled: `enableBrightnessControl = true` in `home-manager/dms.nix:9`
- Brightness slider widget configured in DMS control center (lines 79-82)
- Brightness control package: `brightnessctl` (installed in both `home-manager/dms.nix:315` and `home-manager/niri/default.nix:17`)
- Niri keyboard shortcuts: XF86MonBrightnessUp/Down mapped to `brightnessctl` commands (`home-manager/niri/binds.nix:171-172`)

### Root Cause

The issue has multiple layers:

1. **brightnessctl Limitation**
   - `brightnessctl` only works with devices exposed through the kernel's backlight interface
   - Running `brightnessctl -l` shows only the laptop's backlight device: `amdgpu_bl1`
   - External monitors don't expose brightness controls through the kernel backlight interface

2. **External Monitors Require DDC/CI**
   - External monitors use the DDC/CI (Display Data Channel Command Interface) protocol
   - DDC/CI communicates over the I2C bus to control monitor settings
   - Requires the `i2c-dev` kernel module to expose I2C devices as `/dev/i2c-*`

3. **Missing Kernel Module**
   - The `i2c-dev` kernel module is not loaded by default
   - Without it, no `/dev/i2c*` devices exist
   - Running `ddcutil detect` confirms: "No /dev/i2c devices exist. ddcutil requires module i2c-dev."
   - While `ddcutil` is already installed on the system, it cannot function without the kernel module

4. **DMS Limitation**
   - DankMaterialShell's brightness control widget currently only supports `brightnessctl`
   - There is no built-in DDC/CI or `ddcutil` integration for external monitors
   - The brightness slider widget will continue to only control the laptop screen

## Solution

### Step 1: Enable i2c-dev Kernel Module

Add the `i2c-dev` kernel module to your NixOS configuration to enable DDC/CI communication with external monitors.

**Option A: Add to `modules/system/core.nix`** (recommended for system-wide configuration):
```nix
{ pkgs, lib, ... }:

{
  boot.initrd.systemd.enable = true;
  security.tpm2.enable = true;

  # Enable I2C device access for external monitor control (DDC/CI)
  boot.kernelModules = [ "i2c-dev" ];

  networking.networkmanager.enable = true;
  # ... rest of configuration
}
```

**Option B: Add to `hosts/framework/default.nix`** (for Framework-specific configuration):
```nix
{ nixos-hardware, lanzaboote, lib, ... }:

{
  imports = [ /* ... */ ];

  # Enable I2C device access for external monitor control (DDC/CI)
  boot.kernelModules = [ "i2c-dev" ];

  boot.loader.systemd-boot.enable = lib.mkForce false;
  # ... rest of configuration
}
```

After adding this configuration:
```bash
sudo nixos-rebuild switch
reboot
```

### Step 2: Verify DDC/CI Functionality

After rebooting, verify that the i2c-dev module is loaded and external monitors are detected:

```bash
# Check if i2c devices exist
ls -la /dev/i2c*

# Check if i2c-dev module is loaded
lsmod | grep i2c_dev

# Detect external monitors
ddcutil detect

# Get capabilities of your external monitor
ddcutil capabilities
```

### Step 3: Control External Monitor Brightness

Once DDC/CI is working, you can control external monitor brightness using `ddcutil`:

```bash
# Get current brightness (VCP code 10 is brightness)
ddcutil getvcp 10

# Set brightness to 50%
ddcutil setvcp 10 50

# Set brightness to 100%
ddcutil setvcp 10 100

# Get all supported VCP codes for your monitor
ddcutil capabilities
```

### Optional: Add Custom Niri Keybindings

To control external monitor brightness with keyboard shortcuts, you can add custom bindings to `home-manager/niri/binds.nix`:

```nix
# External monitor brightness control (using ddcutil)
# Note: Replace "DP-3" with your actual monitor identifier from `ddcutil detect`
"Mod+XF86MonBrightnessUp".action.spawn = [
  "sh" "-c"
  "current=$(ddcutil getvcp 10 --terse | cut -d' ' -f4); new=$((current + 5)); ddcutil setvcp 10 $new"
];

"Mod+XF86MonBrightnessDown".action.spawn = [
  "sh" "-c"
  "current=$(ddcutil getvcp 10 --terse | cut -d' ' -f4); new=$((current - 5)); [ $new -lt 0 ] && new=0; ddcutil setvcp 10 $new"
];
```

This allows you to use:
- **Brightness keys**: Control laptop screen (existing functionality)
- **Mod + Brightness keys**: Control external monitor (new functionality)

### Alternative: Use brightnessDevicePins in DMS

The `brightnessDevicePins` setting in `home-manager/dms.nix:221` might allow pinning specific monitors to specific brightness control methods, but this feature is not well-documented. Further investigation into DMS source code or documentation would be needed.

## Technical Details

### How brightnessctl Works
- Accesses kernel's sysfs backlight interface: `/sys/class/backlight/`
- Works only with devices that expose brightness controls through the kernel
- Typically works for laptop built-in displays, not external monitors

### How DDC/CI Works
- Uses I2C bus to communicate with monitors
- Implements MCCS (Monitor Control Command Set) protocol
- Requires `i2c-dev` kernel module to expose I2C devices
- Tools like `ddcutil` or `ddccontrol` can communicate via DDC/CI
- Supports various controls: brightness, contrast, color temperature, input source, etc.

### I2C Modules on Framework 13
The following I2C-related modules are loaded by default:
- `i2c_piix4`: I2C bus driver
- `i2c_smbus`: SMBus protocol support
- `i2c_hid_acpi`: HID over I2C for input devices
- `i2c_hid`: Generic I2C HID support
- `i2c_algo_bit`: Bit-banging algorithm for I2C

However, `i2c-dev` (which exposes I2C devices to userspace as `/dev/i2c-*`) is not loaded by default.

## Limitations

1. **DMS Control Panel**: The brightness slider in DMS control panel will continue to only control the laptop screen. It does not have DDC/CI integration.

2. **ddcutil Performance**: DDC/CI commands can be relatively slow (100-200ms per command) compared to native backlight controls.

3. **Monitor Compatibility**: Not all monitors fully support DDC/CI. Some may have limited or non-functional implementations.

4. **USB-C Docks**: Some USB-C docks may not properly pass through DDC/CI commands. Direct USB-C connection to monitors typically works better.

## Future Improvements

Potential enhancements for better external monitor control:

1. **DMS Integration**: Request DDC/CI support in DankMaterialShell's brightness control
2. **Automatic Monitor Detection**: Script to automatically detect and control the appropriate monitor
3. **Unified Brightness Control**: Wrapper script that uses `brightnessctl` for internal displays and `ddcutil` for external monitors
4. **GUI Application**: Use tools like `ddcui` (Qt-based GUI for ddcutil) for easier manual control

## Related Files

- `home-manager/dms.nix`: DMS configuration, brightness control enabled
- `home-manager/niri/binds.nix`: Keyboard shortcuts for brightness control
- `home-manager/niri/outputs.nix`: Display output configuration
- `modules/system/core.nix`: System-level configuration (add kernel modules here)
- `hosts/framework/default.nix`: Framework-specific configuration

## References

- [ddcutil Documentation](https://www.ddcutil.com/)
- [ddcutil GitHub Repository](https://github.com/rockowitz/ddcutil)
- [DDC/CI Protocol](https://en.wikipedia.org/wiki/Display_Data_Channel)
- [VESA MCCS Standard](https://vesa.org/)
- [DankMaterialShell GitHub](https://github.com/AvengeMedia/DankMaterialShell)

## Date

Investigation completed: 2025-11-07
