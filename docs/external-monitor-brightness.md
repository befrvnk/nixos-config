# External Monitor Brightness Control

## Overview

External monitors connected via USB-C or DisplayPort do not support brightness control through the standard Linux backlight interface. They require DDC/CI (Display Data Channel Command Interface) protocol to adjust brightness and other settings.

## Current Implementation

External monitor brightness control is fully integrated with the standard brightness keys. Both displays stay synchronized.

### How It Works

The `brightness-ctl` script (`home-manager/niri/default.nix`) provides unified control:

1. **Internal display**: Adjusted via `brightnessctl` (synchronous) with swayosd OSD feedback
2. **External monitors**: Synced to internal brightness via `ddcutil` in background

The external monitor always catches up to match the internal display's brightness percentage. Rapid keypresses are handled gracefully - the external monitor syncs to the final value.

### Sync Mechanism

```
Keypress → brightnessctl (sync) → Read % → Write target file → Show OSD
                                              ↓
                              Background: ddcutil syncs to target
                                              ↓
                              Loop until target stops changing
```

- A lock file prevents multiple ddcutil processes from running simultaneously
- If target changes while ddcutil is running, it syncs again after completion
- This ensures the external monitor always reaches the final brightness value

### Configuration

| Component | Location |
|-----------|----------|
| I2C access (`hardware.i2c.enable`) | `modules/system/core.nix` |
| User in `i2c` group | `modules/users.nix` |
| ddcutil package | `home-manager/packages.nix` |
| `brightness-ctl` script | `home-manager/niri/default.nix` |
| Keyboard bindings | `home-manager/niri/binds.nix` |

### Manual Control

```bash
# Detect external monitors
ddcutil detect

# Get current brightness (VCP code 10 is brightness)
ddcutil getvcp 10

# Set brightness to 50%
ddcutil setvcp 10 50

# Get all supported VCP codes for your monitor
ddcutil capabilities
```

## Technical Details

### Why brightnessctl Instead of swayosd

The script uses `brightnessctl` to change brightness because it's **synchronous** - it returns only after sysfs is updated. This avoids a race condition where reading brightness immediately after `swayosd-client --brightness raise` could return a stale value.

The OSD is then shown via `swayosd-client --custom-progress` with the actual brightness value.

### How DDC/CI Works
- Uses I2C bus to communicate with monitors
- Implements MCCS (Monitor Control Command Set) protocol
- Requires `i2c-dev` kernel module to expose I2C devices
- User must be in `i2c` group for permission to access `/dev/i2c-*`
- Commands are slow (~100-200ms) compared to native backlight

### I2C Modules on Framework 13
The following I2C-related modules are loaded by default:
- `i2c_piix4`: I2C bus driver
- `i2c_smbus`: SMBus protocol support
- `i2c_hid_acpi`: HID over I2C for input devices
- `i2c_hid`: Generic I2C HID support
- `i2c_algo_bit`: Bit-banging algorithm for I2C

The `i2c-dev` module is enabled via `hardware.i2c.enable = true` in `modules/system/core.nix`.

## Limitations

1. **ddcutil Performance**: DDC/CI commands are slow (~100-200ms). The script runs ddcutil in the background so OSD feedback remains instant.

2. **Monitor Compatibility**: Not all monitors fully support DDC/CI. Some may have limited or non-functional implementations.

3. **USB-C Docks**: Some USB-C docks may not properly pass through DDC/CI commands. Direct USB-C connection to monitors typically works better.

## Troubleshooting

### Verify i2c-dev module is loaded
```bash
lsmod | grep i2c_dev
ls -la /dev/i2c*
```

### Check user is in i2c group
```bash
groups | grep i2c
```

### Check if monitor is detected
```bash
ddcutil detect
```

### Permission denied errors
Ensure `hardware.i2c.enable = true` is set and user is in `i2c` group. Reboot after changes.

### External monitor not syncing
Check the target file and lock file:
```bash
cat /tmp/brightness-ctl-target
ls -la /tmp/brightness-ctl-ddc.lock
```

If lock file exists but no ddcutil is running, remove it:
```bash
rm /tmp/brightness-ctl-ddc.lock
```

## References

- [ddcutil Documentation](https://www.ddcutil.com/)
- [ddcutil GitHub Repository](https://github.com/rockowitz/ddcutil)
- [DDC/CI Protocol](https://en.wikipedia.org/wiki/Display_Data_Channel)
- [VESA MCCS Standard](https://vesa.org/)
