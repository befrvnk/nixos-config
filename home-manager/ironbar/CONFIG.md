# Ironbar Configuration Notes

## config.json

### Volume Module

**Location in config:** Lines 77-86

```json
{
  "type": "custom",
  "class": "volume",
  "bar": [
    {
      "type": "label",
      "label": "{{200:~/.config/ironbar/modules/volume/volume-status.sh}}"
    }
  ]
}
```

**Why custom instead of built-in:**
The built-in volume module (`{"type": "volume"}`) is **NOT used** due to a critical crash bug (GitHub issue #875). Instead, we use a custom script-based module.

**Configuration details:**
- `200` = Polling interval in milliseconds (5 updates/second)
- Provides near-instant feedback when volume changes
- Performance impact: negligible (<0.1% CPU)

**Alternative polling intervals:**
- `500ms` - More conservative, still responsive (2 updates/sec)
- `1000ms` - Standard refresh rate but noticeable delay (1 update/sec)

**To switch back to built-in module (when bug is fixed):**
Replace the custom module block with:
```json
{
  "type": "volume",
  "max_volume": 100
}
```

Also remove from `default.nix`:
- `pkgs.wireplumber` from home.packages
- The `xdg.configFile."ironbar/modules/volume/..."` entry

### Module Order

Modules in the center bar (left to right):
1. Workspaces
2. Clock
3. System Info (CPU, Memory, Temperature)
4. WiFi (custom)
5. Notifications (custom)
6. Bluetooth
7. **Volume (custom)** ← Added here
8. Battery (custom)

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
