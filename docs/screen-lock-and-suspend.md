# Screen Lock and Suspend Behavior

This document describes how screen locking and system suspend work in this NixOS configuration.

## Overview

The system uses **stasis** as the primary idle manager. Stasis is a modern, event-driven Wayland idle manager that:
1. Monitors user activity via libinput (requires `input` group membership)
2. Detects media playback via PipeWire/PulseAudio (pactl)
3. Inhibits idle for specific applications (configurable)
4. Triggers lock and suspend actions based on configurable timeouts

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
- Stasis monitors PipeWire sink inputs via `pactl`
- `monitor_media true` enables automatic media detection
- Active audio streams inhibit idle actions

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
- Stasis triggers lock at 300 seconds
- Stasis triggers suspend at 305 seconds
- Pre-suspend command locks screen before suspend

---

### Scenario 3: Specific Applications Running

**Timeline:**
- **Screen stays on** while inhibiting app is running
- Depends on `inhibit_apps` configuration

**What you experience:**
- Certain applications (browsers, media players) prevent idle
- Useful for reading, video calls without audio

**Technical details:**
- `inhibit_apps` list in stasis config specifies app IDs
- Current inhibitors: spotify, mpv, vlc, firefox, zen-beta
- Stasis matches running applications by their Wayland app_id

---

### Scenario 4: Lid Close (Anytime)

**Timeline:**
- **Immediate** - System suspends (handled by systemd-logind)
- **On wake** - Screen lock requires password

**What you experience:**
- Close lid → System suspends immediately
- Open lid → Enter password to unlock

**Technical details:**
- Lid close handled by systemd-logind, not stasis
- `HandleLidSwitch = "suspend"` in logind config
- Stasis `pre_suspend_command` ensures screen is locked

---

### Scenario 5: External Monitor with Lid Closed

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

### Stasis Idle Manager
**File:** `home-manager/stasis.nix`
- Stasis configuration (timeouts, inhibitors, media monitoring)
- Swaylock configuration (appearance, theming)

### System-Level Suspend Settings
**File:** `modules/system/core.nix`
- `HandleLidSwitch = "suspend"` - Lid close always suspends
- `HandleLidSwitchDocked = "ignore"` - Ignore lid when docked
- `HandleLidSwitchExternalPower = "suspend"` - Suspend on lid close even when plugged in
- `IdleAction = "ignore"` - Don't auto-suspend (managed by stasis instead)

### User Groups
**File:** `modules/users.nix`
- User must be in `input` group for stasis to detect activity via libinput

---

## How Stasis Works

Stasis is an event-driven idle manager with multiple detection methods:

1. **Activity detection via libinput** - Monitors keyboard/mouse input directly
   - Requires user membership in `input` group
   - Resets idle timer on any input event

2. **Media detection via PipeWire** - Uses `pactl list sink-inputs`
   - Detects actively playing audio streams
   - Ignores paused/corked streams
   - `monitor_media true` enables this feature

3. **Application inhibition** - Matches running apps by ID
   - `inhibit_apps` list specifies which apps prevent idle
   - Useful for apps that don't use audio (reading, video calls)

4. **Wayland idle-inhibit protocol** - Respects application requests
   - Applications can request idle inhibition directly
   - Stasis honors these requests automatically

### Configuration Options

```rune
default:
  monitor_media true           # Detect playing audio
  debounce_seconds 2           # Debounce activity events

  inhibit_apps [               # Apps that prevent idle
    "spotify"
    "mpv"
    "vlc"
    "firefox"
    "zen-beta"
  ]

  pre_suspend_command "swaylock -f"  # Lock before suspend

  lock_screen:
    timeout 300                # Lock after 5 minutes
    command "swaylock -f"
  end

  suspend:
    timeout 305                # Suspend 5 seconds after lock
    command "systemctl suspend"
  end
end
```

---

## Troubleshooting

### Screen locks while watching videos
**Cause:** Media detection not working

**Check stasis status:**
```bash
stasis info
```
Should show `Media Players Playing: 1` or higher when audio is playing.

**If media shows 0:**
- Verify `pactl` is installed: `which pactl`
- Check audio streams: `pactl list sink-inputs`

---

### Idle timer doesn't reset on mouse/keyboard activity
**Cause:** User not in `input` group

**Check group membership:**
```bash
groups
```
Should include `input`.

**If missing:**
- Add `"input"` to `extraGroups` in `modules/users.nix`
- Rebuild and **reboot** (group changes require new login session)

---

### Screen doesn't stay on for specific apps
**Cause:** App not in `inhibit_apps` list

**Check current inhibitors:**
```bash
stasis info
```
Shows `InhibitApps` list and `Apps Inhibiting` count.

**Find app ID:**
```bash
niri msg windows | grep app_id
```

**Add to config:** Edit `home-manager/stasis.nix` and add the app ID to `inhibit_apps`.

---

### Manual control

**Pause stasis (prevent lock/suspend):**
```bash
stasis pause
```

**Resume stasis:**
```bash
stasis resume
```

**Toggle manual inhibition:**
```bash
stasis toggle-inhibit
```

**Check status:**
```bash
stasis info
```

---

## Customization

### Adjust idle timeouts

Edit `home-manager/stasis.nix`:

```rune
lock_screen:
  timeout 600  # 10 minutes instead of 5
  command "swaylock -f"
end

suspend:
  timeout 610  # Suspend 10 seconds after lock
  command "systemctl suspend"
end
```

### Add applications to inhibit list

Edit `home-manager/stasis.nix`:

```rune
inhibit_apps [
  "spotify"
  "mpv"
  "vlc"
  "firefox"
  "zen-beta"
  "your-app-id"  # Add new app here
]
```

### Disable auto-suspend entirely

Remove the suspend block from `home-manager/stasis.nix`:

```rune
# Delete or comment out:
# suspend:
#   timeout 305
#   command "systemctl suspend"
# end
```

---

## Summary Table

| Scenario | Screen | Locks? | Suspends? | Audio continues? |
|----------|--------|--------|-----------|------------------|
| Audio/video playing | Stays on | No | No | Yes |
| Inhibiting app running | Stays on | No | No | N/A |
| No media/apps | Locks at 5 min | Yes | Yes (5:05) | N/A |
| Lid close | Locks | Yes | Yes | Pauses |
| External monitor + lid closed | Normal | Depends | Depends | Depends |
| Manual pause (`stasis pause`) | Stays on | No | No | Yes |

---

## Ironbar Integration

The display popup in Ironbar shows "Stay On" toggle that controls stasis:
- **ON**: Manually inhibits idle (same as `stasis toggle-inhibit`)
- **OFF**: Normal idle behavior

Scripts location: `home-manager/ironbar/modules/display/`

---

## Related Files

- `home-manager/stasis.nix` - Stasis idle manager and swaylock configuration
- `home-manager/niri/startup.nix` - Stasis spawn-at-startup
- `home-manager/ironbar/modules/display/` - Stay-on toggle scripts
- `modules/users.nix` - Input group for activity detection
- `modules/system/core.nix` - System-level power management
