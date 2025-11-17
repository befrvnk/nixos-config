# Fingerprint Sensor Setup

This guide covers the setup and usage of the fingerprint sensor on the Framework 13 laptop.

## Overview

The fingerprint sensor is configured using `fprintd` with the Goodix TOD driver for optimal Framework laptop compatibility. Fingerprint authentication is enabled for:

- **swaylock** - Unlock your screen with your fingerprint
- **1Password** - Authenticate 1Password with your fingerprint (via polkit)
- **sudo** - Execute sudo commands with your fingerprint
- **login** - Login to your system with your fingerprint

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

- Lock your screen (Mod+Shift+Escape or after idle timeout) and unlock with your fingerprint
- Run a sudo command and use your fingerprint when prompted
- Open 1Password and try authenticating with your fingerprint

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

## Tips

- **Enroll multiple fingers**: Enroll both index fingers for convenience
- **Quality matters**: Ensure your finger is clean and dry during enrollment
- **Multiple scans**: The enrollment process requires multiple scans to capture different parts of your fingerprint
- **Fallback**: You can always use your password if fingerprint authentication fails

## Security Notes

- Fingerprints are stored locally in `/var/lib/fprint/`
- The fingerprint sensor uses the Goodix TOD (Touch OEM Drivers) for enhanced security
- Fingerprint authentication is configured as "sufficient" - it tries fingerprint first, but falls back to password
- This means you can still access your system even if the fingerprint sensor fails
