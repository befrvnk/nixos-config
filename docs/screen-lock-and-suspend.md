# Screen Lock and Suspend Behavior

This document describes how screen locking and system suspend work in this NixOS configuration.

## Overview

The system uses three main components to manage screen locking and suspend:
1. **swayidle** - Monitors user inactivity and triggers lock/suspend actions
2. **wayland-pipewire-idle-inhibit** - Prevents idle (screen lock/off) when audio is playing via PipeWire
3. **spotify-suspend-handler** - Pauses/resumes Spotify during suspend to prevent crashes

## Behavior Scenarios

### Scenario 1: Idle with Media Playing (YouTube, Spotify, etc.)

**Timeline:**
- **Screen stays on** - idle is inhibited while audio plays
- **System never locks or suspends**
- **Media continues playing**

**What you experience:**
- As long as audio is playing through PipeWire, the screen stays on
- No password prompt, no screen dimming
- Works with any application that outputs audio

**Technical details:**
- `wayland-pipewire-idle-inhibit` monitors PipeWire audio streams
- When audio is detected (for 5+ seconds), it inhibits idle via Wayland protocol
- swayidle's timeouts are not triggered

---

### Scenario 2: Idle without Media Playing

**Timeline:**
- **5:00** - Screen locks (password required)
- **5:05** - **System suspends**

**What you experience:**
- Screen locks after 5 minutes of idle
- System suspends 5 seconds later
- Wake requires unlocking with password

**Technical details:**
- No audio playing = no idle inhibition
- swayidle triggers lock at 300 seconds
- swayidle triggers suspend at 305 seconds

---

### Scenario 3: Lid Close (Anytime)

**Timeline:**
- **Immediate** - Screen locks
- **Immediate** - Spotify pauses (if playing)
- **Immediate** - System suspends
- **On wake** - Spotify resumes (if it was playing)

**What you experience:**
- Close lid → System suspends immediately (even if media is playing)
- Open lid → Enter password to unlock
- Spotify automatically resumes if it was playing

**Technical details:**
- `before-sleep` event triggers swaylock
- `spotify-suspend-handler` detects `PrepareForSleep` signal
- Checks if Spotify is playing, pauses it, saves state to `/tmp/spotify-was-playing-$USER`
- On resume, waits 2 seconds for audio devices, then resumes playback

---

### Scenario 4: External Monitor with Lid Closed

**Timeline:**
- **No automatic actions**
- System behaves as if lid is open
- Follows Scenario 1 or 2 based on media playback

**What you experience:**
- Can work normally with external monitor and lid closed
- Idle behavior still depends on audio playback state

**Technical details:**
- `HandleLidSwitchDocked = "ignore"` in systemd-logind config
- System only responds to idle timeouts, not lid state

---

## Configuration Files

### Screen Lock and Idle Timeout
**File:** `home-manager/swaylock.nix`
- swaylock configuration (appearance, theming)
- swayidle timeouts (5 minutes lock, 5:05 suspend)
- wayland-pipewire-idle-inhibit service configuration

### Spotify Crash Prevention
**File:** `home-manager/spotify-suspend/default.nix`
- **Service:** `spotify-suspend-handler`
  - Pauses Spotify before suspend, resumes after wake
  - Prevents crashes from audio device disconnection

### System-Level Suspend Settings
**File:** `modules/system/core.nix`
- `HandleLidSwitch = "suspend"` - Lid close always suspends
- `HandleLidSwitchDocked = "ignore"` - Ignore lid when docked
- `HandleLidSwitchExternalPower = "suspend"` - Suspend on lid close even when plugged in
- `IdleAction = "ignore"` - Don't auto-suspend (managed by swayidle instead)

---

## How wayland-pipewire-idle-inhibit Works

Unlike the previous polling-based approach, wayland-pipewire-idle-inhibit is event-driven:

1. **Monitors PipeWire** for audio stream activity
2. **Ignores short sounds** (< 5 seconds) like notification sounds
3. **Uses Wayland idle-inhibit protocol** to prevent screen lock/off
4. **Releases inhibition** when audio stops

### Configuration Options

```nix
services.wayland-pipewire-idle-inhibit = {
  enable = true;
  settings = {
    verbosity = "WARN";           # Logging level
    media_minimum_duration = 5;   # Ignore sounds < 5 seconds
    idle_inhibitor = "wayland";   # Use Wayland protocol
  };
};
```

---

## Troubleshooting

### Screen locks while watching videos
**Cause:** wayland-pipewire-idle-inhibit service not running or audio not routing through PipeWire

**Check:**
```bash
systemctl --user status wayland-pipewire-idle-inhibit
```
Should show: `active (running)`

**Also check:**
```bash
wpctl status
```
Verify audio is playing through PipeWire sinks.

---

### Spotify crashes after suspend
**Cause:** Audio device disconnects during suspend, CEF framework crashes

**Solution:** Already implemented in `spotify-suspend/default.nix`
- Automatically pauses Spotify before suspend
- Resumes playback after wake (2-second delay for audio devices)

**Verify it's working:**
```bash
systemctl --user status spotify-suspend-handler
```
Should show: `active (running)`

---

### Screen doesn't stay on during audio playback
**Cause:** wayland-pipewire-idle-inhibit not detecting audio

**Check service logs:**
```bash
journalctl --user -u wayland-pipewire-idle-inhibit -f
```

**Possible causes:**
- Audio duration < 5 seconds (increase `media_minimum_duration`)
- Audio not routing through PipeWire
- Application using different audio backend

---

## Customization

### Adjust idle timeouts

Edit `home-manager/swaylock.nix`:

```nix
timeouts = [
  {
    timeout = 300;  # Change this (in seconds)
    command = "${pkgs.swaylock}/bin/swaylock -f";
  }
  {
    timeout = 305;  # Suspend 5 seconds after lock
    command = "${pkgs.systemd}/bin/systemctl suspend";
  }
];
```

### Adjust audio duration threshold

Edit `home-manager/swaylock.nix`:

```nix
services.wayland-pipewire-idle-inhibit.settings = {
  media_minimum_duration = 10;  # Ignore sounds < 10 seconds
};
```

### Disable auto-suspend entirely

Remove the suspend timeout from `home-manager/swaylock.nix`:

```nix
# Delete or comment out this section:
# {
#   timeout = 305;
#   command = "${pkgs.systemd}/bin/systemctl suspend";
# }
```

---

## Summary Table

| Scenario | Screen | Locks? | Suspends? | Audio continues? |
|----------|--------|--------|-----------|------------------|
| Audio/video playing | Stays on | No | No | Yes |
| No media | Locks at 5 min | Yes | Yes (5:05) | N/A |
| Lid close | Locks | Yes | Yes | No (Spotify pauses) |
| External monitor + lid closed | Normal | Depends | Depends | Depends |

---

## Related Files

- `home-manager/swaylock.nix` - Screen lock and idle inhibit configuration
- `home-manager/spotify-suspend/default.nix` - Spotify crash prevention
- `modules/system/core.nix` - System-level power management
