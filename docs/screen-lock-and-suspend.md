# Screen Lock and Suspend Behavior

This document describes how screen locking and system suspend work in this NixOS configuration.

## Overview

The system uses three main components to manage screen locking and suspend:
1. **swayidle** - Monitors user inactivity and triggers actions
2. **inhibit-suspend-while-playing** - Prevents auto-suspend when media is playing
3. **spotify-suspend-handler** - Pauses/resumes Spotify during suspend to prevent crashes

## Behavior Scenarios

### Scenario 1: Idle with Media Playing (YouTube, Spotify, etc.)

**Timeline:**
- **5:00** - Screen turns off (no lock screen)
- **5:05** - Suspend is **blocked** by inhibitor
- **5:10** - Display remains off (fallback check)
- **Media continues playing throughout**

**What you experience:**
- Screen turns off after 5 minutes of idle
- Move mouse/keyboard to wake screen (no password needed)
- YouTube/music keeps playing
- System never suspends

**Technical details:**
- `playerctl status` detects "Playing" state
- Smart lock script (`smartLock`) turns off screen instead of locking
- `inhibit-suspend-while-playing` service holds systemd "idle" inhibitor lock
- System suspend is blocked while inhibitor is active

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
- `playerctl status` returns "Stopped" or "Paused"
- Smart lock script locks screen normally
- No inhibitor lock active
- `systemctl suspend` executes successfully

---

### Scenario 3: Lid Close (Anytime)

**Timeline:**
- **Immediate** - Screen locks
- **Immediate** - Spotify pauses (if playing)
- **Immediate** - System suspends
- **On wake** - Spotify resumes (if it was playing)

**What you experience:**
- Close lid → System suspends immediately
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
- Auto-suspend still depends on media playback state

**Technical details:**
- `HandleLidSwitchDocked = "ignore"` in systemd-logind config
- System only responds to idle timeouts, not lid state

---

## Configuration Files

### Screen Lock and Idle Timeout
**File:** `home-manager/swaylock.nix`
- Defines idle timeouts (5 minutes)
- Smart lock logic (media-aware)
- Suspend trigger (5 seconds after lock)

### Media Playback Detection
**File:** `home-manager/media-suspend.nix`
- **Service 1:** `inhibit-suspend-while-playing`
  - Monitors all MPRIS-compatible players
  - Blocks auto-suspend when media is playing
  - Works with: Spotify, YouTube (Firefox/Chrome), VLC, etc.

- **Service 2:** `spotify-suspend-handler`
  - Spotify-specific crash prevention
  - Pauses before suspend, resumes after wake
  - Only affects Spotify, not other players

### System-Level Suspend Settings
**File:** `modules/system/core.nix`
- `HandleLidSwitch = "suspend"` - Lid close always suspends
- `HandleLidSwitchDocked = "ignore"` - Ignore lid when docked
- `HandleLidSwitchExternalPower = "suspend"` - Suspend on lid close even when plugged in
- `IdleAction = "ignore"` - Don't auto-suspend (managed by swayidle instead)

---

## Media Player Compatibility

The system detects media playback using **MPRIS** (Media Player Remote Interfacing Specification).

### Supported Players:
- ✅ **Web browsers** (YouTube, Netflix, etc.)
  - Firefox
  - Chromium/Chrome
  - Zen Browser
- ✅ **Music players**
  - Spotify
  - VLC
  - MPV (with MPRIS support)
- ✅ **Most Linux media applications** that implement MPRIS

### Detection Command:
```bash
playerctl status
```
Returns: `Playing`, `Paused`, or `Stopped`

---

## Troubleshooting

### Screen locks while watching videos
**Cause:** Media player doesn't support MPRIS or isn't reporting playback state

**Check:**
```bash
playerctl status
```
Should return `Playing` when video is active. If not, the player doesn't support MPRIS.

**Workaround:** Use a different player or browser that supports MPRIS.

---

### Spotify crashes after suspend
**Cause:** Audio device disconnects during suspend, CEF framework crashes

**Solution:** Already implemented in `media-suspend.nix`
- Automatically pauses Spotify before suspend
- Resumes playback after wake (2-second delay for audio devices)

**Verify it's working:**
```bash
systemctl --user status spotify-suspend-handler
```
Should show: `active (running)`

---

### System suspends while playing music
**Cause:** Inhibitor service not running

**Check:**
```bash
systemctl --user status inhibit-suspend-while-playing
```
Should show: `active (running)`

**Check current inhibitors:**
```bash
systemd-inhibit --list
```
Should show "Audio Playback" inhibitor when media is playing.

---

## Customization

### Adjust idle timeouts

Edit `home-manager/swaylock.nix`:

```nix
timeouts = [
  {
    timeout = 300;  # Change this (in seconds)
    command = "${smartLock}";
  }
  # ...
];
```

### Disable smart locking (always lock, even with media)

Edit `home-manager/swaylock.nix`, replace `smartLock` with direct swaylock:

```nix
{
  timeout = 300;
  command = "${pkgs.swaylock}/bin/swaylock -f";
}
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

| Scenario | After 5 min idle | Locks? | Suspends? | Media continues? |
|----------|------------------|--------|-----------|------------------|
| YouTube playing | Screen off | ❌ No | ❌ No | ✅ Yes |
| Spotify playing | Screen off | ❌ No | ❌ No | ✅ Yes |
| No media | Screen locked | ✅ Yes | ✅ Yes (5:05) | N/A |
| Lid close | Immediate | ✅ Yes | ✅ Yes | ❌ No (pauses) |
| External monitor + lid closed | Normal behavior | Depends | Depends | Depends |

---

## Related Files

- `home-manager/swaylock.nix` - Screen lock configuration
- `home-manager/media-suspend.nix` - Media playback and suspend inhibition
- `modules/system/core.nix` - System-level power management
- `docs/screen-lock-and-suspend.md` - This documentation
