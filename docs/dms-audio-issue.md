# DMS Audio Control Issue - Investigation Report

**Date**: 2025-11-07
**Status**: Issue identified, workaround available, permanent fix pending upstream

## Problem Description

The DMS (DankMaterialShell) control panel volume slider shows 0% and does not respond to user input. The slider cannot control audio volume, and changing the value has no effect on the actual system volume.

- **Observed behavior**: Volume slider stuck at 0%, no response to changes
- **Expected behavior**: Volume slider should reflect current volume and allow adjustment
- **Output device**: Framework Speakers (selected and correct)
- **System audio**: Working correctly via `wpctl` commands and keyboard shortcuts

## Root Cause Analysis

### Technical Details

DMS runs on **Quickshell**, a Qt Quick-based desktop shell framework that integrates with PipeWire through native bindings (`Quickshell.Services.Pipewire` module).

The Framework laptop configuration enables audio enhancement:

```nix
# hosts/framework/default.nix:32-36
hardware.framework.laptop13.audioEnhancement = {
  enable = true;
  hideRawDevice = false;
  rawDeviceName = "alsa_output.pci-0000_c1_00.6.HiFi__Speaker__sink";
};
```

This creates a PipeWire filter-chain with the following characteristics:

**Filter-chain node (ID 77/78)**:
```
node.name = "audio_effect.laptop-convolver"
node.description = "Framework Speakers"
media.class = "Audio/Sink"
object.register = "false"  ← KEY ISSUE
node.virtual = "false"
node.group = "filter-chain-2396-18"
```

**Raw hardware node (ID 53)**:
```
node.name = "alsa_output.pci-0000_c1_00.6.HiFi__Speaker__sink"
node.description = "Family 17h/19h/1ah HD Audio Controller Speaker"
media.class = "Audio/Sink"
(object.register property not set, defaults to true)
```

### The Issue

The filter-chain node has **`object.register = "false"`**, which prevents Quickshell from properly binding to it. This is evidenced by error logs:

```
ERROR quickshell.service.pipewire.node: Tried to change node volumes for PwNode(0x7f8e130061c0, id=78/unbound) which is not bound.
```

Quickshell's PipeWire integration requires binding nodes using `PwObjectTracker`, but nodes with `object.register = false` cannot be bound, making their volume/mute properties return invalid data (displayed as 0%).

### Why wpctl Commands Work

The `wpctl` CLI tool communicates through **WirePlumber**, which properly routes commands through the filter-chain hierarchy to the actual hardware device. It doesn't require direct node binding like Quickshell does.

## Audio Enhancement Pipeline

The Framework audioEnhancement creates a sophisticated audio processing pipeline:

1. **Bankstown LV2 Plugin** - Psychoacoustic bass extension
2. **LSP Loudness Compensation** - Maintains consistent sound across volume levels
3. **LSP 8-Band Parametric Equalizer** - "Lappy McTopface" profile tuned for Framework 13
4. **LSP Multiband Compressor** - Woofer compression settings
5. **LSP Compressor** - Final limiter for protection

This configuration comes from the nixos-hardware Framework module:
- Source: `nixos-hardware.nixosModules.framework-amd-ai-300-series`
- Implemented in: `framework/13-inch/common/audio.nix`

## Testing Results

### Test 1: Direct Hardware Control
```bash
wpctl set-default 53  # Set raw hardware as default
```

**Result**:
- ✅ DMS volume slider works perfectly
- ❌ Audio enhancement is bypassed (audio quality degraded)

### Test 2: Manual Volume Control
```bash
wpctl set-volume @DEFAULT_AUDIO_SINK@ 50%
```

**Result**:
- ✅ Works regardless of default sink
- This is how keyboard shortcuts work (defined in `home-manager/niri/binds.nix`)

## Available Solutions

### Option 1: Disable Audio Enhancement (Workaround)

Modify `hosts/framework/default.nix`:

```nix
hardware.framework.laptop13.audioEnhancement = {
  enable = false;  # Disable filter-chain
};
```

**Pros**: DMS controls work immediately
**Cons**: Lose audio quality improvements (bass, EQ, loudness compensation)

### Option 2: Override Filter-Chain Configuration (Needs Investigation)

Potentially override the `object.register` property in the filter-chain configuration:

```nix
# This approach needs investigation - may require:
# - Custom WirePlumber configuration
# - Override of nixos-hardware audio module
# - Custom filter-chain.conf
```

**Pros**: Keep both audio enhancement and DMS controls
**Cons**: Requires deeper dive into PipeWire/WirePlumber configuration

### Option 3: Report Upstream Issues

Two potential upstream fixes:

1. **nixos-hardware**: Request to make `object.register` configurable or default to `true`
2. **Quickshell**: Request better support for binding to filter-chain nodes with `object.register = false`

**Pros**: Fixes root cause for all users
**Cons**: Takes time, depends on upstream maintainers

### Option 4: Use Command-Based Volume Control in DMS

Modify DMS configuration to use `wpctl` commands instead of native PipeWire bindings:

```nix
# Hypothetical - DMS may not support this
programs.dankMaterialShell.useCommandBasedAudio = true;
```

**Pros**: Works with any audio configuration
**Cons**: May not be supported by DMS, requires upstream feature

## Current Workaround

Keyboard shortcuts work because they use `wpctl` commands:

```nix
# home-manager/niri/binds.nix:164-169
"XF86AudioLowerVolume".action.spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"];
"XF86AudioMute".action.spawn = ["wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"];
"XF86AudioRaiseVolume".action.spawn = ["wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"];
```

**Recommendation**: Continue using keyboard shortcuts for volume control until a permanent solution is implemented.

## References

### Configuration Files
- DMS config: `home-manager/dms.nix`
- Framework config: `hosts/framework/default.nix`
- PipeWire config: `modules/services/pipewire.nix`
- Audio keybinds: `home-manager/niri/binds.nix`

### Audio Nodes
- Filter-chain sink: Node 77 (`audio_effect.laptop-convolver`)
- Raw hardware sink: Node 53 (`alsa_output.pci-0000_c1_00.6.HiFi__Speaker__sink`)

### System Services
- DMS service: `systemctl --user status dms.service`
- Filter-chain service: `systemctl --user status filter-chain.service`
- View logs: `journalctl --user -u dms.service -f`

### Useful Commands
```bash
# Check audio status
wpctl status

# Inspect nodes
wpctl inspect 77  # Filter-chain
wpctl inspect 53  # Raw hardware

# Change default sink
wpctl set-default <node-id>

# Test volume control
wpctl set-volume @DEFAULT_AUDIO_SINK@ 50%
wpctl get-volume @DEFAULT_AUDIO_SINK@
```

## Next Steps

1. Investigate PipeWire/WirePlumber configuration options for overriding `object.register`
2. Check if DMS/Quickshell has alternative audio backend configuration
3. Consider reporting issue to nixos-hardware for Framework audio module
4. Monitor upstream Quickshell issues for filter-chain binding support

## Additional Notes

- The brightness slider in DMS control panel has the same issue and needs separate investigation
- PulseAudio compatibility layer is enabled and working correctly
- WirePlumber is functioning properly - this is a Quickshell-specific binding issue
