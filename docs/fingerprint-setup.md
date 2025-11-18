# Fingerprint Sensor Setup

This guide covers the setup and usage of the fingerprint sensor on the Framework 13 laptop.

## Overview

The fingerprint sensor is configured using `fprintd` (version 1.94.5). Modern Framework laptops work with regular fprintd without needing TOD drivers. Fingerprint authentication is enabled for:

- **swaylock** - Unlock your screen with your fingerprint
- **sudo** - Execute sudo commands with your fingerprint
- **login** - Login to your system with your fingerprint
- **Polkit authorization** - System authorization dialogs (including some 1Password operations)

### 1Password Limitations

**Important**: 1Password on Linux does **not** support biometric authentication for unlocking the vault. You must use your master password to unlock 1Password. This is a limitation of 1Password on Linux, not this configuration.

Fingerprint authentication will work for:
- ✓ Polkit authorization prompts (e.g., browser extension integration)
- ✗ Unlocking the 1Password vault (requires master password)

## Configuration

The fingerprint configuration is located in `modules/hardware/fprintd.nix`. The module:

1. Enables the fprintd service with the Goodix TOD driver
2. Configures PAM (Pluggable Authentication Modules) for fingerprint support
3. Sets up authentication to try fingerprint first, then fall back to password

## Enrolling Your Fingerprints

Use `fprintd-enroll` to register your fingerprints:

```bash
# Enroll a fingerprint for your user
fprintd-enroll

# Or specify a specific finger
fprintd-enroll -f right-index-finger
```

Available finger options:
- `left-thumb`, `left-index-finger`, `left-middle-finger`, `left-ring-finger`, `left-little-finger`
- `right-thumb`, `right-index-finger`, `right-middle-finger`, `right-ring-finger`, `right-little-finger`

Follow the on-screen prompts and scan your finger multiple times when requested (usually 5 times) to ensure good coverage.

### Verify Enrollment

Check which fingerprints are enrolled:

```bash
fprintd-list $USER
```

Example output:
```
found 1 devices
Device at /net/reactivated/Fprint/Device/0
Using device /net/reactivated/Fprint/Device/0
Fingerprints for user frank on Goodix MOC Fingerprint Sensor (press):
 - #0: right-index-finger
```

### Test Authentication

Try using your fingerprint:

- **Screen lock**: Lock your screen (Mod+Shift+Escape or after idle timeout) and unlock with your fingerprint
- **sudo**: Run a sudo command and use your fingerprint when prompted
- **System login**: Login to your system with your fingerprint

Note: You cannot use fingerprint to unlock the 1Password vault on Linux.

## Managing Fingerprints

### List Enrolled Fingerprints

```bash
fprintd-list $USER
```

### Delete a Fingerprint

```bash
# Delete a specific finger
fprintd-delete <username> -f right-index-finger

# Delete all fingerprints for a user
fprintd-delete <username>
```

### Re-enroll a Fingerprint

If a fingerprint isn't working well:

```bash
# Delete the old enrollment
fprintd-delete $USER -f right-index-finger

# Enroll again
fprintd-enroll -f right-index-finger
```

## Troubleshooting

### Fingerprint Reader Not Detected

Check if the fingerprint device is recognized:

```bash
lsusb | grep -i fingerprint
```

You should see a Goodix fingerprint device listed.

### Authentication Not Working

1. Verify fingerprints are enrolled:
   ```bash
   fprintd-list $USER
   ```

2. Check if fprintd service is running:
   ```bash
   systemctl status fprintd
   ```

3. Test fingerprint verification:
   ```bash
   fprintd-verify
   ```

### Service Not Starting

Check fprintd logs:

```bash
journalctl -u fprintd -f
```

## What Works and What Doesn't

### Works ✓
- **swaylock** - Screen unlock
- **sudo** - Command authorization
- **login** - System login
- **Polkit dialogs** - System authorization requests (e.g., 1Password browser extension integration)

### Doesn't Work ✗
- **1Password vault unlock** - Requires master password (1Password Linux limitation, not a configuration issue)

## Fallback to Password Authentication

The fingerprint authentication is configured to automatically fall back to password if fingerprint fails or times out.

### Quick Fallback Options

1. **Wait for timeout**: After 10 seconds, it will automatically fall back to password (recommended)
2. **Press Ctrl+C**: Cancel fingerprint authentication (requires fprintd 1.92+, now supported with regular fprintd)
3. **Start typing password**: Some PAM implementations may accept this (not always reliable)

**Note**: The previous TOD (Touch OEM Drivers) variant didn't support Ctrl+C. The configuration has been updated to use regular fprintd 1.94.5 which includes this feature.

### Using Laptop with Lid Closed

When using your laptop with the lid closed and external monitor:
- The system automatically stops fprintd when lid is closed (fingerprint unavailable)
- When lid is opened, fprintd automatically starts again
- This prevents unnecessary fingerprint timeout delays when using external monitor

To disable this automatic lid management, remove `./hardware/fprintd-lid-management.nix` from `modules/default.nix`.

## Tips

- **Enroll multiple fingers**: Enroll both index fingers for convenience
- **Quality matters**: Ensure your finger is clean and dry during enrollment
- **Multiple scans**: The enrollment process requires multiple scans to capture different parts of your fingerprint
- **Fallback always available**: You can always use your password if fingerprint authentication fails
- **Timeout configured**: Fingerprint timeout is set to 10 seconds for faster fallback

## Security Notes

- Fingerprints are stored locally in `/var/lib/fprint/`
- The fingerprint sensor uses the Goodix TOD (Touch OEM Drivers) for enhanced security
- Fingerprint authentication is configured as "sufficient" - it tries fingerprint first, but falls back to password
- This means you can still access your system even if the fingerprint sensor fails
