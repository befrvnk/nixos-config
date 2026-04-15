# Ironbar Configuration Notes

## config.json

### Volume Module

```json
{
  "type": "custom",
  "class": "volume",
  "bar": [
    {
      "type": "label",
      "label": "{{1000:~/.config/ironbar/modules/volume/volume-status.sh}}"
    }
  ]
}
```

**Why custom instead of built-in:**
The built-in volume module (`{"type": "volume"}`) is **not used** due to a critical crash bug (GitHub issue #875).

**Current behavior:**
- `volume-status.sh` only reads `~/.cache/volume-status`
- `volume-ctl` in the Niri config updates that cache whenever volume changes
- Niri runs `volume-ctl init` once at startup to seed the cache
- `1000` = the bar reads the cache once per second

This keeps the bar simple and avoids direct PipeWire polling from ironbar itself.

### Module Layout

The config is split across `start`, `center`, and `end` sections:
- `start`: firewall summary and system stats
- `center`: aurora, weather, clock, notifications
- `end`: tray, storage, WiFi, Bluetooth, peripheral battery, volume, display, battery

### Custom Modules

All custom modules use the same pattern:
```json
{
  "type": "custom",
  "class": "module-name",
  "bar": [
    {
      "type": "label",
      "label": "{{INTERVAL:PATH_TO_SCRIPT}}"
    }
  ]
}
```

Where:
- `INTERVAL` = Milliseconds between script executions
- `PATH_TO_SCRIPT` = Path relative to `~/.config/`
