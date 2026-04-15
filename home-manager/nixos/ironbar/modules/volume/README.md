# Custom Volume Module for Ironbar

## Why This Exists

Ironbar's built-in volume module (`type: "volume"`) has a **critical crash bug** that can abort the bar with PulseAudio mainloop assertion failures.

**GitHub Issue:** [#875 - Crashing on pulseaudio](https://github.com/JakeStanger/ironbar/issues/875)

## Current Design

The volume display is intentionally split into two pieces:

1. **`volume-ctl`** (from `home-manager/nixos/niri/default.nix`)
   - handles raise/lower/mute actions
   - drives SwayOSD
   - updates `~/.cache/volume-status`
2. **`volume-status.sh`**
   - reads the cached label from `~/.cache/volume-status`
   - prints it for ironbar

This means ironbar never queries PipeWire or `wpctl` directly for its volume label.

## How It Works

### On startup

Niri runs:

```bash
volume-ctl init
```

That seeds `~/.cache/volume-status` before the bar starts polling.

### On volume changes

The Niri keybindings call `volume-ctl raise`, `volume-ctl lower`, or `volume-ctl mute-toggle`.
Those commands update the cache after changing volume, so the bar just picks up the new text on the next read.

### In ironbar

`config.json` uses:

```json
"label": "{{1000:~/.config/ironbar/modules/volume/volume-status.sh}}"
```

That is a **1 second cache read**, not a PipeWire query.

## Benefits

- avoids the built-in crash path entirely
- keeps the bar decoupled from volume control logic
- eliminates direct bar-side PipeWire polling
- keeps the display logic easy to debug

## Fallback Behavior

If the cache file does not exist yet, `volume-status.sh` returns `󰖁 N/A`.
Normally this only happens before the initial `volume-ctl init` has run.

## Debugging

Inspect the cached label:

```bash
cat ~/.cache/volume-status
```

Refresh the cache manually:

```bash
volume-ctl init
```

Test the reader script:

```bash
bash ~/.config/ironbar/modules/volume/volume-status.sh
```
