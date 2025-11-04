# Waybar with Niri Overview-Only Mode

This configuration sets up Waybar to only appear when Niri's overview (expose) mode is active, saving screen space during normal usage while providing a status bar when needed.

## How It Works

### Components

1. **default.nix**: Home-manager module that configures waybar and the systemd service
2. **toggle-waybar.py**: Python script that listens to niri events and shows/hides waybar
3. **config.jsonc**: Reference configuration (actual config is in default.nix as Nix attributes)
4. **style.css**: CSS styling with color scheme integration

### Script Behavior

The `toggle-waybar.py` script:
1. Connects to niri's IPC socket via `$NIRI_SOCKET`
2. Requests the event stream from niri
3. Starts waybar as a subprocess
4. Waits for waybar to initialize (non-blocking with 5s timeout)
5. **Hides waybar initially** (waybar starts visible by default)
6. Listens for `OverviewOpenedOrClosed` events
7. Shows waybar when `is_open: true`, hides when `is_open: false`

### Waybar Configuration Requirements

For the toggle to work, waybar must have:
```json
{
  "layer": "overlay",
  "exclusive": false
}
```

These settings allow waybar to respond to `SIGUSR1` signals for show/hide toggling.

## Key Learnings & Solutions

### Issue #1: Script Blocking Forever
**Problem**: Script blocked on `waybar_proc.stdout.readline()` waiting for `"[info] Bar configured"` message, never reaching the hide step.

**Solution**: Use `select.poll()` for non-blocking I/O with a 5-second timeout:
```python
poller = poll()
poller.register(waybar_proc.stdout.fileno(), POLLIN)
while not configured and (time() - start_time) < 5.0:
    events = poller.poll(100)  # Poll every 100ms
    if events:
        line = waybar_proc.stdout.readline()
```

**Why**: Non-blocking approach that reads actual output but has a fallback timeout. Better than just sleeping because it's output-dependent.

### Issue #2: Waybar Visible by Default
**Problem**: Waybar starts visible when launched, so we need to hide it immediately after initialization.

**Solution**: After waybar initializes, send the first `SIGUSR1` to hide it:
```python
toggle_waybar()  # First toggle hides it
waybar_visible = False
```

### Issue #3: Wrong Event Key Name
**Problem**: We checked `event.get("open")` but the actual key is `"is_open"`, so it always returned False.

**Debugging Approach**: Added logging to see full event structure:
```python
print(f"Full overview event: {overview_event}", flush=True)
# Output: {'is_open': True}
```

**Solution**: Use the correct key:
```python
overview_open = overview_event.get("is_open", False)
```

### Issue #4: State Tracking Required
**Problem**: Blindly toggling on every `OverviewOpenedOrClosed` event caused waybar to be in the wrong state because the event fires for both opening and closing.

**Solution**: Track waybar's visibility state and only toggle when the desired state differs:
```python
waybar_visible = False  # Current state
should_be_visible = overview_event.get("is_open", False)
if should_be_visible != waybar_visible:
    toggle_waybar()
    waybar_visible = should_be_visible
```

### Issue #5: Debug Output Not Appearing in Logs
**Problem**: Debug print statements weren't showing in `journalctl`.

**Solution**: Always use `flush=True`:
```python
print("Message here", flush=True)
```

This ensures output appears immediately in systemd logs without buffering.

### Issue #6: Nix Files Need to be in Git
**Problem**: After creating new files, Nix couldn't find them during rebuild.

**Solution**: Flakes only see files tracked by git:
```bash
git add home-manager/waybar/
```

Files don't need to be committed, just staged (added).

## Making Changes

### Modifying Waybar Configuration

Edit `home-manager/waybar/default.nix`:
- **Modules**: Change `modules-left`, `modules-center`, `modules-right`
- **Module settings**: Edit the configuration under each module name
- **Available modules**: See waybar documentation or `man waybar`

After editing:
```bash
sudo nixos-rebuild switch
```

### Modifying Waybar Styling

Waybar's styling is managed by `stylix`. The base style is located in `home-manager/waybar/style.css`, but the colors are injected by `stylix` automatically.

To change the theme, edit `modules/stylix.nix`.

After editing `style.css` or `modules/stylix.nix`:
```bash
sudo nixos-rebuild switch
```

### Modifying Toggle Script

Edit `home-manager/waybar/toggle-waybar.py`:
- Script is copied to Nix store during rebuild
- Changes **require rebuild** (not just systemctl restart)

After editing:
```bash
sudo nixos-rebuild switch
```

### Testing Without Full Rebuild

To test script changes quickly:
```bash
# Stop the service
systemctl --user stop waybar

# Run updated script directly
python3 home-manager/waybar/toggle-waybar.py

# Press Ctrl+C when done testing
# Then do proper rebuild
```

## Debugging

### View Live Logs
```bash
journalctl --user -u waybar -f
```

### Check Service Status
```bash
systemctl --user status waybar
```

### Restart Service
```bash
systemctl --user restart waybar
```

### Verify Niri Events
The script logs all overview events:
```
Full overview event: {'is_open': True}
Parsed overview state: is_open=True
State change: False -> True
Toggled waybar visibility
```

### Manual Toggle Test
```bash
# Get waybar PID
pgrep waybar

# Send SIGUSR1 to toggle visibility
kill -SIGUSR1 <pid>
```

## Color Scheme Integration

Colors are automatically managed by `stylix`. The theme is set in `modules/stylix.nix`.
`stylix` generates the stylesheet for `waybar` automatically.

## Modules Currently Configured

- **niri/workspaces**: Workspace indicators
- **niri/window**: Active window title
- **clock**: Date and time
- **cpu**: CPU usage percentage
- **memory**: RAM usage percentage
- **network**: WiFi/Ethernet status
- **battery**: Battery percentage and status

Each module can be customized or removed in `default.nix`.

## References

- [Niri IPC Documentation](https://github.com/YaLTeR/niri/wiki/IPC)
- [Waybar Documentation](https://github.com/Alexays/Waybar/wiki)
- [Original Discussion](https://github.com/YaLTeR/niri/discussions/1591)
- [Waybar Man Page](https://man.archlinux.org/man/waybar.5.en)
- [Waybar Niri Modules](https://man.archlinux.org/man/extra/waybar/waybar-niri-workspaces.5.en)
