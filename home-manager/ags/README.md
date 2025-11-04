# AGS Configuration for Niri

Custom AGS (Aylur's GTK Shell) configuration for Niri window manager with GNOME-like interface.

## Features

### Status Bar
- **Left Section**:
  - Niri workspace indicators with active/focused states
  - Window icons for current workspace
- **Center Section**:
  - Date and time display (clickable to open calendar popup)
- **Right Section**:
  - CPU usage indicator
  - AMD GPU usage indicator (via radeontop)
  - WiFi status
  - Bluetooth indicator
  - Volume indicator
  - Battery indicator

### Calendar Popup
- Monthly calendar view
- Notifications list with dismiss functionality
- Media player controls (play/pause, previous, next)
- Keyboard shortcut: ESC to close

### Control Panel
- Volume slider with percentage
- Microphone slider with percentage
- Brightness slider with percentage
- Quick toggles:
  - WiFi on/off
  - Bluetooth on/off
  - Do Not Disturb mode
- Keyboard shortcut: ESC to close

## Structure

```
ags/
├── app.ts                    # Main application entry point
├── package.json              # NPM dependencies
├── tsconfig.json             # TypeScript configuration
├── style.scss                # GNOME-like styling
├── services/
│   └── niri.ts              # Niri IPC client for workspace/window management
└── widgets/
    ├── Bar.tsx              # Main bar component
    ├── NiriWorkspaces.tsx   # Workspace indicators
    ├── NiriWindows.tsx      # Window icons
    ├── DateTime.tsx         # Date/time display
    ├── SystemIndicators.tsx # System status indicators
    ├── CalendarPopup.tsx    # Calendar with notifications and media
    └── ControlPanel.tsx     # GNOME-like quick settings panel
```

## Dependencies

- `radeontop` - AMD GPU monitoring
- `brightnessctl` - Brightness control
- `mako` - Notification daemon
- `libnotify` - Notification library
- Astal libraries (provided by AGS)

## Usage

The configuration is automatically loaded by home-manager. After building your system:

```bash
# Rebuild your NixOS configuration
sudo nixos-rebuild switch --flake .
```

### Interactions

- Click on workspaces to switch
- Click on window icons to focus windows
- Click on date/time to toggle calendar popup
- Click on system indicators to toggle control panel
- Press ESC to close popups

## Customization

### Colors
Edit `style.scss` to customize colors and styling. The current theme uses Catppuccin-inspired colors.

### Widgets
All widgets are in the `widgets/` directory. Each widget is a self-contained TypeScript/React component.

### Niri Integration
The `services/niri.ts` file handles communication with Niri via IPC. It polls every 500ms for workspace and window updates.

## Troubleshooting

### Niri socket not found
Ensure `NIRI_SOCKET` environment variable is set. This should be automatic when running Niri.

### GPU monitoring not working
Check that `radeontop` is installed and you have permissions to access GPU metrics:
```bash
# Test radeontop
radeontop -d - -l 1
```

### Brightness control not working
Ensure `brightnessctl` is installed and you have permissions:
```bash
# Test brightnessctl
brightnessctl set 50%
```

## Future Enhancements

- [ ] Bluetooth device list in control panel
- [ ] Network list in control panel
- [ ] Night light toggle functionality
- [ ] Better notification management
- [ ] Workspace renaming
- [ ] Window previews on hover
