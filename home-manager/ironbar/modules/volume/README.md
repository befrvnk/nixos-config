# Custom Volume Module for Ironbar

## Why This Exists

Ironbar's built-in volume module (`type: "volume"`) has a **critical crash bug** that causes ironbar to abort with PulseAudio mainloop assertion failures.

### The Bug

**Error Message:**
```
Assertion 'e->mainloop->n_enabled_defer_events > 0' failed at ../src/pulse/mainloop.c:261, function mainloop_defer_enable(). Aborting.
```

**GitHub Issue:** [#875 - Crashing on pulseaudio](https://github.com/JakeStanger/ironbar/issues/875)
- Status: Open (as of 2025-11-14)
- Labels: Critical, Bug, Help Wanted
- Affects: Ironbar 0.16.1+, PipeWire with PulseAudio compatibility

**Root Cause:**
Race condition in PulseAudio's mainloop when streams are rapidly created/destroyed. The Rust PulseAudio bindings used by ironbar don't properly synchronize mainloop operations, causing the assertion to fail.

## Solution

This custom module uses **wpctl** (WirePlumber CLI) instead of PulseAudio bindings, completely avoiding the mainloop crash.

### How It Works

1. **Script:** `volume-status.sh` queries WirePlumber's in-memory state via `wpctl get-volume @DEFAULT_AUDIO_SINK@`
2. **Display:** Shows icon + percentage (e.g., `󰕾 75%`)
3. **Update Rate:** Polls every 200ms (5 times per second)

### Technical Details

- **No PulseAudio bindings:** Uses CLI instead of library calls
- **Works with filters:** Uses `@DEFAULT_AUDIO_SINK@` which resolves to any configured default (including audio effect filters)
- **Fast:** `wpctl` execution time ~2-5ms, minimal CPU usage
- **Responsive:** 200ms polling provides near-instant visual feedback

## Configuration

### Polling Interval

Set in `config.json`:
```json
"label": "{{200:~/.config/ironbar/modules/volume/volume-status.sh}}"
         ^^^^
         200ms = 5 updates/second
```

**Performance Impact:** Negligible (<0.1% CPU)

**Alternatives:**
- 500ms = 2 updates/second (more conservative)
- 1000ms = 1 update/second (noticeable delay)

### Icons

Uses Nerd Font icons that match the existing ironbar aesthetic:
- `󰖁` - Muted or 0% volume
- `󰕿` - Low (1-32%)
- `󰖀` - Medium (33-65%)
- `󰕾` - High (66-100%)

## Future

When [issue #875](https://github.com/JakeStanger/ironbar/issues/875) is fixed:
1. Test the built-in volume module
2. If stable, can switch back to `{"type": "volume", "max_volume": 100}`
3. Remove this custom module if no longer needed

## Debugging

Test the script manually:
```bash
bash ~/.config/ironbar/modules/volume/volume-status.sh
```

Check WirePlumber status:
```bash
wpctl status
wpctl get-volume @DEFAULT_AUDIO_SINK@
```
