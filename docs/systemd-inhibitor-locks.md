# Systemd Inhibitor Locks

## What Are Inhibitor Locks?

Inhibitor locks are a systemd mechanism that allows processes to temporarily block certain system actions. Think of them as a way for applications to say "wait, don't do that yet - I'm busy!"

When a process creates an inhibitor lock, it tells systemd: "Don't perform this action (like suspending or shutting down) until I say it's okay."

## How They Work

A process creates an inhibitor lock by running `systemd-inhibit` with specific parameters. The lock remains active as long as the `systemd-inhibit` process is running. When the process terminates, the lock is automatically released.

### Example

```bash
# Block system from auto-suspending while this runs
systemd-inhibit --what=idle --who="My App" --why="Processing data" sleep 3600
```

This command:
1. Creates an `idle` inhibitor lock
2. Identifies itself as "My App"
3. Explains the reason as "Processing data"
4. Keeps the lock active for 1 hour (or until terminated)

## Types of Inhibitor Locks

Controlled by the `--what` parameter:

| Type | Blocks | Use Case |
|------|--------|----------|
| **`idle`** | Auto-suspend/idle actions | Prevent system from going idle (used by media players) |
| **`sleep`** | Manual suspend/hibernate | Prevent lid close or manual suspend (critical operations) |
| **`shutdown`** | System shutdown/reboot | Prevent shutdown during updates or backups |
| **`handle-power-key`** | Power button action | Custom power button handling |
| **`handle-suspend-key`** | Suspend key action | Custom suspend key handling |
| **`handle-lid-switch`** | Lid close action | Custom lid close handling |

You can combine multiple types:
```bash
systemd-inhibit --what=idle:sleep:shutdown ...
```

## Two Modes

Controlled by the `--mode` parameter:

- **`block`** (default) - Hard block: the action is completely prevented until the lock is released
- **`delay`** - Soft block: the action is delayed briefly (a few seconds) to allow cleanup, then proceeds anyway

### Example Comparison

```bash
# Block mode - suspend is COMPLETELY prevented
systemd-inhibit --what=idle --mode=block sleep infinity

# Delay mode - suspend is delayed by a few seconds for cleanup
systemd-inhibit --what=sleep --mode=delay ./cleanup-script.sh
```

## Viewing Active Inhibitor Locks

You can see all currently active inhibitor locks:

```bash
systemd-inhibit --list
```

Example output:
```
WHO            UID  USER  PID     COMM            WHAT  WHY                      MODE
Audio Playback 1000 frank 3584232 systemd-inhibit idle  Music is playing         block
NetworkManager 0    root  123456  NetworkManager  sleep Network reconfiguration delay
```

This shows:
- **WHO**: Application/service name
- **UID/USER**: User ID and username
- **PID**: Process ID holding the lock
- **COMM**: Command name
- **WHAT**: Type of inhibitor
- **WHY**: Reason for the lock
- **MODE**: Block or delay mode

## How This Configuration Uses Inhibitor Locks

### Media Playback Suspend Prevention

The `inhibit-suspend-while-playing` service (`home-manager/media-suspend/default.nix`) creates an `idle` inhibitor lock to prevent auto-suspend when media is playing.

**Configuration:** `home-manager/media-suspend/inhibit-suspend-while-playing.sh`

#### How It Works

1. **Detection Loop**: Every 5 seconds, the script checks if any MPRIS-compatible media player is playing:
   ```bash
   status=$(playerctl status 2>/dev/null || echo "Stopped")
   ```

2. **Create Lock When Playing**: If status is "Playing" and no lock exists:
   ```bash
   systemd-inhibit --what=idle --who="Audio Playback" --why="Music is playing" \
     --mode=block sleep infinity &
   inhibitor_pid=$!
   ```
   - The `sleep infinity` keeps the inhibitor process running indefinitely
   - The PID is saved so we can terminate it later

3. **Release Lock When Stopped**: If status is not "Playing" and a lock exists:
   ```bash
   kill "$inhibitor_pid" 2>/dev/null
   ```
   - Terminating the `systemd-inhibit` process automatically releases the lock

#### What It Prevents

- ✅ **Prevents**: Auto-suspend from swayidle timeouts (the 305-second timeout)
- ❌ **Does NOT prevent**: Manual suspend (lid close, explicit `systemctl suspend`)

#### Why Only `idle` Inhibitor?

The script uses `--what=idle` instead of `--what=sleep` because:
- **`idle` inhibitor**: Prevents automatic/timeout-based suspends (what we want)
- **`sleep` inhibitor**: Would also prevent lid close suspend (not desirable - closing lid should always suspend)

### Supported Media Players

Any MPRIS-compatible media player is detected:
- ✅ Web browsers (YouTube, Netflix in Firefox/Chrome/Zen)
- ✅ Spotify
- ✅ VLC
- ✅ MPV (with MPRIS support)
- ✅ Most Linux media applications

### Spotify Crash Prevention

The `spotify-suspend-handler` service handles a separate issue: Spotify crashes when the system suspends while playing.

**How it works:**
1. Listens for systemd's `PrepareForSleep` signal
2. Before suspend: Pauses Spotify if playing, saves state
3. After resume: Waits 2 seconds for audio devices, then resumes playback

This uses a `delay` mode sleep inhibitor to perform cleanup before suspend.

## Troubleshooting

### Check If Locks Are Working

```bash
# Start playing media (YouTube, Spotify, etc.)
playerctl status  # Should show "Playing"

# Check for inhibitor lock
systemd-inhibit --list | grep "Audio Playback"
# Should show one lock with your username

# Stop media
playerctl status  # Should show "Stopped" or "Paused"

# Wait 5 seconds, then check again
systemd-inhibit --list | grep "Audio Playback"
# Should show no locks
```

### System Still Suspends During Media Playback

**Possible causes:**

1. **Service not running:**
   ```bash
   systemctl --user status inhibit-suspend-while-playing
   ```
   Should show `active (running)`.

2. **Media player doesn't support MPRIS:**
   ```bash
   playerctl status
   ```
   Should return "Playing" when media is active. If not, the player doesn't support MPRIS.

3. **Multiple inhibitor locks (bug in script):**
   ```bash
   systemd-inhibit --list | grep "Audio Playback" | wc -l
   ```
   Should show `0` when no media is playing, `1` when media is playing. If you see multiple locks, the script has a bug.

### Orphaned Inhibitor Locks

If you see multiple "Audio Playback" locks piling up:

1. **Restart the service:**
   ```bash
   systemctl --user restart inhibit-suspend-while-playing
   ```

2. **Check script logs for errors:**
   ```bash
   journalctl --user -u inhibit-suspend-while-playing -f
   ```

3. **Manually kill orphaned locks** (emergency cleanup):
   ```bash
   pkill -f "systemd-inhibit.*Audio Playback"
   ```

## Related Files

- **Script implementation:** `home-manager/media-suspend/inhibit-suspend-while-playing.sh`
- **Service definition:** `home-manager/media-suspend/default.nix`
- **Idle timeout config:** `home-manager/swaylock.nix`
- **Overview documentation:** `docs/screen-lock-and-suspend.md`
