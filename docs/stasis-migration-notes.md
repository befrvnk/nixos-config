# Stasis Migration Notes

This document captures the issues encountered when migrating from swayidle to stasis (January 2026). We rolled back to swayidle due to unresolved issues with lid close handling.

## Why We Tried Stasis

Stasis is a modern, event-driven Wayland idle manager that promised:
- Built-in media detection (no separate service needed)
- App-based inhibition by Wayland app_id
- Event-driven architecture (no polling)
- Manual control via CLI (pause/resume/toggle-inhibit)
- D-Bus/logind integration for lid events and suspend/resume

## Issues Encountered and Solutions

### Issue 1: Config Parsing Error

**Symptom:** `config must contain a 'default:' block`

**Cause:** RUNE configuration language requires specific structure.

**Solution:** Ensure config has proper `default:` block at top level with `end` closing it.

---

### Issue 2: Logind Session Detection Failed

**Symptom:** `logind liveness probe failed: PID does not belong to any known session`

**Cause:** When using `niri-session`, Niri is started via `systemctl --user start niri.service`, which places it in `user@1000.service/session.slice/` instead of the logind session scope (`session-*.scope`). Processes spawned by Niri (including stasis) end up in `user@1000.service/app.slice/`, which logind's `GetSessionByPID` doesn't recognize as part of the session.

**Investigation:**
```bash
# Check process cgroup
cat /proc/$(pgrep -x stasis)/cgroup
# Shows: 0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-niri-...

# Check session scope
systemctl status session-3.scope
# Only contains: greetd, gnome-keyring, niri-session, systemctl
# Does NOT contain: niri, stasis, or any apps
```

**Solution:** Changed greetd to use `niri --session` directly instead of `niri-session`:
```nix
# modules/desktop/greetd.nix
command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd '${pkgs.niri}/bin/niri --session'";
```

This keeps Niri and all spawned processes in the logind session scope.

---

### Issue 3: D-Bus/Logind Integration Disabled

**Symptom:** `D-Bus: loginctl integration disabled; skipping login1 monitoring`

**Cause:** `enable_loginctl` is only set to true when a lock action has `use_loginctl true`.

**Solution:** Added `use_loginctl true` to the lock_screen action:
```rune
lock_screen:
  timeout 300
  command "swaylock -f"
  use_loginctl true
end
```

---

### Issue 4: False Positive Media Detection

**Symptom:** `Media Players Playing: 2` when nothing is actually playing.

**Cause:** Stasis uses `pactl list sink-inputs` for media detection, not MPRIS. The `audio-keep-alive` service (pacat playing silence) and the Framework audio enhancement filter chain were detected as "playing media".

**Solution:** Added `media_blacklist` to exclude system audio streams:
```rune
media_blacklist [
  "pacat"
  "Framework"
]
```

---

### Issue 5: Lid Close Does Not Lock Screen (UNRESOLVED)

**Symptom:** Closing and opening the laptop lid returns directly to the desktop without showing swaylock.

**Cause:** Stasis does NOT take a systemd inhibitor lock. The sequence is:
1. User closes lid
2. Logind sends `PrepareForSleep` D-Bus signal
3. Logind immediately suspends (no inhibitors to wait for)
4. Stasis receives the signal but has no time to run `pre_suspend_command`
5. System wakes up without lock screen

**Why this is a stasis limitation:**
- Proper suspend handling requires taking a "delay" inhibitor lock
- This tells systemd to wait before suspending
- The service runs its pre-suspend command, then releases the lock
- Stasis doesn't implement this pattern

**Attempted workarounds:**
1. Using `lid_close_action "lock-screen"` - Doesn't help because logind suspends before stasis can act
2. Setting `HandleLidSwitch = "ignore"` to let stasis handle via UPower - Would work but adds complexity
3. Creating a separate systemd service with inhibitor - Works but defeats the purpose of stasis as "single source of truth"

**Comparison with swayidle:**
- swayidle's `before-sleep` event works because swayidle is started by the session and the lock command runs synchronously before suspend completes
- The timing is different - swayidle hooks into the suspend process earlier

---

## Final Configuration Before Rollback

```nix
# home-manager/stasis.nix
stasisConfig = ''
  @author "frank"
  @description "Framework laptop idle management with stasis"

  default:
    monitor_media true
    debounce_seconds 2

    inhibit_apps [
      "mpv"
      "vlc"
    ]

    media_blacklist [
      "pacat"
      "Framework"
    ]

    lid_close_action "lock-screen"
    lid_open_action "wake"

    pre_suspend_command "${pkgs.swaylock}/bin/swaylock -f"

    lock_screen:
      timeout 300
      command "${pkgs.swaylock}/bin/swaylock -f"
      use_loginctl true
    end

    dpms_off:
      timeout 303
      command "niri msg action power-off-monitors"
    end

    suspend:
      timeout 310
      command "${pkgs.systemd}/bin/systemctl suspend"
    end
  end
'';
```

---

## What Worked

1. **Idle timeout** - Screen locks after 5 minutes of inactivity ✓
2. **DPMS** - Display turns off shortly after lock ✓
3. **Suspend on idle** - System suspends after configured timeout ✓
4. **Media detection** - Inhibits idle when audio is playing (after blacklist fix) ✓
5. **Manual control** - `stasis pause/resume/toggle-inhibit` commands work ✓
6. **Session detection** - Works after greetd fix ✓

---

## What Didn't Work

1. **Lid close lock** - System suspends before lock screen can appear ✗
2. **Pre-suspend command** - Doesn't run in time due to missing inhibitor lock ✗

---

## Requirements for Future Migration

Before trying stasis again, verify:

1. **Inhibitor lock support** - Stasis should take a delay inhibitor when `pre_suspend_command` is configured
2. **Or** - Find a way to have logind wait for stasis before suspending
3. **Or** - Accept using a separate systemd service for pre-suspend locking

Check stasis GitHub issues/releases for updates on inhibitor support.

---

## Related Links

- Stasis repository: Check flake.nix for the input URL
- logind inhibitor documentation: `man systemd-inhibit`
- Session vs user slice: https://wiki.archlinux.org/title/Systemd/User

---

## Rollback Commit

The stasis migration was introduced in commit `bbfe2e2` and reverted in the subsequent commit.
