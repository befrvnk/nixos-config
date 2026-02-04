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

## Known Issue: Volume Shows 100% on Fresh Boot

### The Problem

On a fresh boot, the Framework audio enhancement filter-chain (`audio_effect.laptop-convolver`) starts in an uninitialized state. In this state:
- `wpctl get-volume` returns `1.00` (100%) regardless of actual volume
- Volume keyboard shortcuts don't apply changes
- The volume display shows incorrect 100%

### Root Cause

The filter-chain node has two suspended states:
1. **Uninitialized (fresh boot):** Volume reports 1.0, changes don't apply
2. **Initialized (after activation):** Volume works correctly, even when suspended

Opening pavucontrol or any app that creates an audio stream activates the sink.

### Solution

A brief `pw-loopback` command at startup initializes the sink. This is configured in `home-manager/niri/startup.nix`:

```nix
{
  command = [
    "${pkgs.bash}/bin/bash"
    "-c"
    "timeout 0.5 ${pkgs.pipewire}/bin/pw-loopback --capture-props='media.class=Audio/Sink' --playback-props='node.target=@DEFAULT_AUDIO_SINK@' || true"
  ];
}
```

This runs for 0.5 seconds at startup, initializes the sink, then exits. After initialization, volume control works correctly even when the sink returns to suspended state.

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

Check sink state (should work regardless of suspended/running after initialization):
```bash
pw-cli info @DEFAULT_AUDIO_SINK@ | grep state
```
