# Waybar with Niri Overview Mode Integration

This document explains our waybar configuration that only appears during Niri's overview (workspace switcher) mode.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Configuration Details](#configuration-details)
- [How It Works](#how-it-works)
- [Pitfalls & Solutions](#pitfalls--solutions)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## Overview

### What is Waybar?

Waybar is a highly customizable Wayland bar for Sway, Hyprland, and other Wayland compositors. It provides:
- Workspace indicators
- Window information
- System tray and status widgets (CPU, memory, network, battery, etc.)
- Clock and calendar
- Custom modules via scripts

### What is Niri Overview Mode?

Niri's overview mode (similar to GNOME's Activities or macOS Mission Control) shows all workspaces and windows in an "expose" view. It's triggered by:
- Super+Tab (default keybinding)
- Swiping up with 3 fingers on trackpad
- `niri msg action overview` command

### Our Setup

We've configured waybar to:
1. **Only appear during Niri overview mode** (hidden during normal desktop use)
2. **Display on the top layer** with system information
3. **Show backdrop wallpaper** from Stylix in overview mode
4. **Integrate with Dunst** for notification management
5. **Use Stylix colors** for consistent theming

This creates a clean desktop experience where the bar only appears when switching workspaces.

## Architecture

### Component Overview

```
┌─────────────────────────────────────────────────────────┐
│                    Niri Compositor                      │
│  - Monitors overview mode state                         │
│  - Emits OverviewOpenedOrClosed events                  │
│  - Manages window layers (backdrop, bottom, top)        │
└──────────────────┬──────────────────────────────────────┘
                   │ IPC via NIRI_SOCKET
                   │
┌──────────────────▼──────────────────────────────────────┐
│            toggle-waybar.py script                      │
│  - Subscribes to Niri event stream                      │
│  - Sends SIGUSR1 (show) when overview opens             │
│  - Sends SIGUSR2 (hide) when overview closes            │
│  - Debounces rapid events (200ms)                       │
└──────────────────┬──────────────────────────────────────┘
                   │ Unix signals
                   │
┌──────────────────▼──────────────────────────────────────┐
│                    Waybar                               │
│  - Starts hidden (start_hidden = true)                  │
│  - Shows on SIGUSR1 (on-sigusr1 = "show")               │
│  - Hides on SIGUSR2 (on-sigusr2 = "hide")               │
│  - Displays modules: workspaces, window, stats          │
└─────────────────────────────────────────────────────────┘
```

### File Structure

```
home-manager/
├── waybar/
│   ├── default.nix          # Main waybar configuration
│   ├── style.css            # Styling with Stylix color placeholders
│   └── toggle-waybar.py     # Python script for overview-mode toggle
├── dunst.nix                # Notification daemon configuration
├── niri/
│   ├── rules.nix            # Layer rules for backdrop wallpaper
│   └── startup.nix          # swaybg for backdrop wallpaper
└── frank.nix                # Imports waybar and dunst modules
```

## Configuration Details

### Waybar Configuration (`home-manager/waybar/default.nix`)

#### Color Integration with Stylix

```nix
{
  pkgs,
  osConfig,
  ...
}: let
  # Use color palette from Stylix
  colors = osConfig.lib.stylix.colors;

  # Read base CSS file
  baseStyle = builtins.readFile ./style.css;

  # Generate CSS with color variables replaced
  styleWithColors = builtins.replaceStrings
    [
      "@base00" "@base01" "@base02" "@base03" "@base04" "@base05" "@base06" "@base07"
      "@base08" "@base09" "@base0A" "@base0B" "@base0C" "@base0D" "@base0E" "@base0F"
    ]
    [
      "#${colors.base00}" "#${colors.base01}" "#${colors.base02}" "#${colors.base03}"
      "#${colors.base04}" "#${colors.base05}" "#${colors.base06}" "#${colors.base07}"
      "#${colors.base08}" "#${colors.base09}" "#${colors.base0A}" "#${colors.base0B}"
      "#${colors.base0C}" "#${colors.base0D}" "#${colors.base0E}" "#${colors.base0F}"
    ]
    baseStyle;
```

This uses Stylix's base16 color scheme to dynamically replace color placeholders in the CSS.

#### Critical Waybar Settings

```nix
programs.waybar = {
  enable = true;
  settings = {
    mainBar = {
      layer = "top";
      position = "top";
      exclusive = false;
      height = 60;

      # Critical for SIGUSR1/SIGUSR2 solution
      start_hidden = true;      # Waybar starts invisible
      on-sigusr1 = "show";      # Show when receiving SIGUSR1
      on-sigusr2 = "hide";      # Hide when receiving SIGUSR2

      # Module layout
      modules-left = ["niri/workspaces" "niri/window"];
      modules-center = ["clock"];
      modules-right = ["cpu" "memory" "custom/notifications" "battery" "network" "bluetooth" "pulseaudio"];
```

#### Notification Integration

```nix
"custom/notifications" = {
  exec = "${pkgs.dunst}/bin/dunstctl count";
  return-type = "json";
  format = "  {}";
  on-click = "${pkgs.dunst}/bin/dunstctl history-pop";
  interval = 1;
};
```

This shows notification count and allows clicking to view notification history.

#### Systemd Service

```nix
systemd.user.services.waybar = {
  Unit = {
    Description = "Waybar with niri overview-only mode";
    PartOf = ["graphical-session.target"];
    After = ["graphical-session.target"];
    ConditionEnvironment = "WAYLAND_DISPLAY";
  };

  Service = {
    Type = "simple";
    ExecStart = "${toggleScript}";  # Runs toggle-waybar.py
    Restart = "on-failure";
    RestartSec = "5s";
  };

  Install = {
    WantedBy = ["graphical-session.target"];
  };
};
```

The service starts the toggle script (not waybar directly), which then manages waybar's lifecycle.

### Toggle Script (`home-manager/waybar/toggle-waybar.py`)

#### Overview

The script:
1. Connects to Niri's IPC socket
2. Subscribes to the event stream
3. Starts waybar (which begins hidden)
4. Listens for `OverviewOpenedOrClosed` events
5. Sends explicit show/hide signals to waybar

#### Key Implementation Details

```python
# Connect to Niri IPC
niri_socket: Socket = Socket(AF_UNIX)
niri_socket.connect(environ["NIRI_SOCKET"])
file: TextIO = niri_socket.makefile("rw")

# Request event stream
file.write('"EventStream"')
file.flush()
niri_socket.shutdown(SHUT_WR)

# Start waybar (starts hidden due to start_hidden = true)
waybar_proc: Popen[str] = Popen(
    ["waybar"],
    stdout=PIPE,
    stderr=PIPE,
    text=True
)
```

#### Signal Handling

```python
def show_waybar() -> None:
    """Send SIGUSR1 to waybar to show it."""
    waybar_proc.send_signal(SIGUSR1)

def hide_waybar() -> None:
    """Send SIGUSR2 to waybar to hide it."""
    waybar_proc.send_signal(SIGUSR2)
```

These functions send Unix signals to the waybar process. Waybar interprets:
- **SIGUSR1** as an explicit "show" command
- **SIGUSR2** as an explicit "hide" command

#### Event Processing with State Tracking

```python
# Track last state to avoid sending duplicate signals
last_visible_state: bool | None = None

for line in file:
    event = loads(line)
    overview_event = event.get("OverviewOpenedOrClosed")
    if overview_event is not None:
        is_open = overview_event.get("is_open", False)

        # Only send signal if state actually changed
        if is_open != last_visible_state:
            print(f"Overview {'opened' if is_open else 'closed'}", flush=True)
            last_visible_state = is_open

            # Explicit show or hide based on overview state
            if is_open:
                show_waybar()
            else:
                hide_waybar()
        else:
            print(f"Ignoring duplicate {'open' if is_open else 'close'} event", flush=True)
```

State tracking ensures:
- **No duplicate signals**: Multiple "open" events only send one show signal
- **Correct final state**: Even with rapid toggling, always reaches the correct final state
- **Processes every transition**: Detects every open→close and close→open state change

This approach is superior to time-based debouncing because debouncing can drop events within a time window, potentially leaving waybar in the wrong state if the final event is ignored.

### Backdrop Wallpaper

#### Niri Startup (`home-manager/niri/startup.nix`)

```nix
spawn-at-startup = [
  # Start swaybg to show Stylix wallpaper on backdrop layer
  { command = [
      "${pkgs.swaybg}/bin/swaybg"
      "-i" "${osConfig.stylix.image}"
      "-m" "fill"
    ];
  }
];
```

#### Layer Rule (`home-manager/niri/rules.nix`)

```nix
layer-rules = [
  # Place swaybg wallpaper on backdrop layer (visible in overview mode)
  {
    matches = [{ namespace = "wallpaper"; }];
    place-within-backdrop = true;
  }
];
```

This places swaybg on the backdrop layer, which is only visible in overview mode.

## How It Works

### Step-by-Step Flow

1. **System Startup**
   - Niri starts and launches swaybg with Stylix wallpaper
   - Systemd starts the `waybar.service`
   - The service executes `toggle-waybar.py`

2. **Script Initialization**
   - Script connects to `$NIRI_SOCKET`
   - Subscribes to event stream with `"EventStream"` message
   - Starts waybar process (waybar remains hidden due to `start_hidden = true`)

3. **User Opens Overview (Super+Tab)**
   - Niri emits `{"OverviewOpenedOrClosed": {"is_open": true}}`
   - Script receives event and calls `show_waybar()`
   - Sends **SIGUSR1** signal to waybar process
   - Waybar executes `on-sigusr1 = "show"` → becomes visible
   - Backdrop wallpaper also becomes visible

4. **User Closes Overview**
   - Niri emits `{"OverviewOpenedOrClosed": {"is_open": false}}`
   - Script receives event and calls `hide_waybar()`
   - Sends **SIGUSR2** signal to waybar process
   - Waybar executes `on-sigusr2 = "hide"` → becomes invisible

### Why SIGUSR1 and SIGUSR2?

Unix signals are the standard IPC mechanism for sending simple commands to processes. There are two user-defined signals:

- **SIGUSR1** (signal 10): User-defined signal 1
- **SIGUSR2** (signal 12): User-defined signal 2

Waybar's implementation:
- `on-sigusr1 = "show"` means "when receiving SIGUSR1, execute the 'show' action"
- `on-sigusr2 = "hide"` means "when receiving SIGUSR2, execute the 'hide' action"

This is **better than toggle** (which waybar also supports via `on-sigusr1 = "toggle"`) because:
- Toggle can get out of sync if signals are missed or duplicated
- Explicit show/hide is **stateless** from the script's perspective
- No need to track or verify waybar's current visibility state

This solution was [suggested by a Reddit user](https://www.reddit.com/r/NixOS/comments/1gn9g4i/comment/lwdlxp8/) who had the same issue.

## Pitfalls & Solutions

### Problem 1: Inverted Visibility

**Issue**: Waybar appeared on desktop and disappeared in overview (opposite of desired behavior).

**Initial Attempts**:
1. Used `on-sigusr1 = "toggle"` with state tracking → state got out of sync
2. Tried inverting the logic (`show when not overview_open`) → still inverted
3. Added state verification with `niri msg overview-state` → unreliable with toggle

**Solution**: Use explicit signals:
- `start_hidden = true` in waybar config
- `on-sigusr1 = "show"` for explicit show
- `on-sigusr2 = "hide"` for explicit hide
- Script sends appropriate signal based on overview state

### Problem 2: Visual Glitches

**Issue**: Gray flickering artifacts where waybar was positioned, especially when using toggle mode.

**Root Cause**: The `SIGUSR1` toggle action left waybar in a partially visible state during transitions.

**Solution**: Explicit show/hide signals completely eliminated the artifacts by ensuring clean state transitions.

### Problem 3: Sync Issues with Rapid Toggling

**Issue**: When rapidly switching between overview and desktop mode, waybar would get out of sync and appear in the wrong mode (e.g., visible on desktop when it should be hidden).

**Initial Attempt**: Time-based debouncing (200ms) to ignore rapid events
**Problem with debouncing**: If events arrive too quickly, the final state event could be dropped, leaving waybar in the wrong state.

**Solution**: State-based event filtering:
```python
last_visible_state: bool | None = None

if is_open != last_visible_state:
    last_visible_state = is_open
    # Send appropriate signal
```

This ensures:
- Every state **transition** is processed (open→close, close→open)
- Duplicate events in the same state are ignored
- Always reaches the correct final state, regardless of event timing

### Problem 4: Dunst Notification Module JSON Error

**Issue**: Waybar crashed on startup with error:
```
[error] custom/notifications: Error parsing JSON: Syntax error: value, object or array expected.
```

**Root Cause**: `dunstctl count` outputs plain text, not JSON:
```
Waiting: 0
  Currently displayed: 0
              History: 20
```

But waybar was configured with `return-type = "json"`.

**Solution**: Create a wrapper script that parses the text and outputs proper JSON:
```nix
notificationScript = pkgs.writeShellScript "dunst-count" ''
  count=$(${pkgs.dunst}/bin/dunstctl count | grep "Waiting" | awk '{print $2}')
  echo "{\"text\":\"$count\",\"tooltip\":\"$count notification(s)\"}"
'';
```

Then use this script in the waybar module:
```nix
"custom/notifications" = {
  exec = "${notificationScript}";
  return-type = "json";
  # ...
};
```

### Problem 5: Missing Backdrop Wallpaper

**Issue**: swaybg was configured but wallpaper didn't appear on backdrop.

**Root Cause**: Layer rule was matching wrong namespace (`"^swaybg$"` instead of `"wallpaper"`).

**Solution**:
1. Check actual namespace with `niri msg layers`
2. Fix rule to match `namespace = "wallpaper"`

## Usage

### Viewing Waybar

Press **Super+Tab** or swipe up with 3 fingers to enter Niri overview mode. Waybar will appear at the top showing:
- **Left**: Niri workspaces, current window title
- **Center**: Clock
- **Right**: CPU, memory, notifications, battery, network, Bluetooth, volume

### Clicking Notification Icon

Click the notification icon (🔔) to view the most recent notification from history.

### Opening System Controls

Click on widgets to open their respective control panels:
- **Bluetooth**: Opens Blueman manager
- **Volume**: Opens PulseAudio Volume Control (pavucontrol)

### Systemd Service Management

```bash
# Check waybar toggle script status
systemctl --user status waybar

# View logs
journalctl --user -u waybar -f

# Restart the service
systemctl --user restart waybar
```

## Troubleshooting

### Waybar Not Appearing in Overview

**Check 1**: Verify the service is running
```bash
systemctl --user status waybar
```

**Check 2**: Check toggle script logs
```bash
journalctl --user -u waybar -f
```

You should see messages like:
```
Starting waybar toggle script...
Connected to niri socket
Starting waybar (starts hidden)...
Listening for niri overview events...
Overview opened
Sent show signal (SIGUSR1) to waybar
```

**Check 3**: Verify NIRI_SOCKET environment variable
```bash
echo $NIRI_SOCKET
# Should output: /run/user/1000/niri.sock or similar
```

**Check 4**: Test manual signals
```bash
# Get waybar PID
pgrep waybar

# Send show signal
kill -SIGUSR1 <PID>

# Send hide signal
kill -SIGUSR2 <PID>
```

### Waybar Visible on Desktop

This indicates the signals are inverted. Check:

1. Waybar config has correct signal mappings:
   ```nix
   on-sigusr1 = "show";  # NOT "hide"
   on-sigusr2 = "hide";  # NOT "show"
   ```

2. Script sends correct signals:
   ```python
   if is_open:
       show_waybar()  # Sends SIGUSR1
   else:
       hide_waybar()  # Sends SIGUSR2
   ```

### Visual Glitches or Flickering

1. Ensure using explicit show/hide (not toggle):
   ```nix
   # ❌ Wrong
   on-sigusr1 = "toggle";

   # ✅ Correct
   on-sigusr1 = "show";
   on-sigusr2 = "hide";
   ```

2. Check debouncing is enabled (200ms default)

3. Increase debounce time if needed:
   ```python
   debounce_seconds: float = 0.3  # Increase from 0.2
   ```

### Backdrop Wallpaper Not Showing

**Check 1**: Verify swaybg is running
```bash
ps aux | grep swaybg
```

**Check 2**: Check layer namespace
```bash
niri msg layers
```

Should show:
```json
{
  "namespace": "wallpaper",
  "layer": "backdrop"
}
```

**Check 3**: Verify layer rule matches namespace
```nix
{
  matches = [{ namespace = "wallpaper"; }];  # NOT "^swaybg$"
  place-within-backdrop = true;
}
```

### Notifications Not Working

**Check 1**: Verify Dunst is running
```bash
systemctl --user status dunst
```

**Check 2**: Test notification
```bash
notify-send "Test" "This is a test notification"
```

**Check 3**: Check notification count
```bash
dunstctl count
```

### Rebuild Issues

If you modify the configuration:

```bash
# Build without switching
nixos-rebuild build --flake .#

# Check for errors
# If successful, remove result symlink
rm -f result

# Apply changes
sudo nixos-rebuild switch --flake .#
```

## Related Documentation

- [Stylix & Darkman Theme Switching Setup](./stylix-darkman-setup.md) - Understanding our theming system
- [Niri IPC Documentation](https://github.com/YaLTeR/niri/wiki/IPC) - Niri's event system
- [Waybar Wiki](https://github.com/Alexays/Waybar/wiki) - Waybar module configuration
- [Unix Signals](https://en.wikipedia.org/wiki/Signal_(IPC)) - Understanding SIGUSR1/SIGUSR2
