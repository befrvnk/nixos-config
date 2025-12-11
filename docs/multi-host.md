# Multi-Host Configuration

This configuration supports multiple NixOS hosts with shared modules and host-specific hardware configurations.

## Overview

The configuration uses a `mkHost` helper function that:
- Centralizes common module imports (home-manager, stylix, overlays)
- Passes host capability flags (`hostConfig`) to modules
- Allows modules to conditionally apply settings based on host capabilities

## Adding a New Host

### 1. Create Host Directory

```bash
mkdir -p hosts/<hostname>
```

### 2. Generate Hardware Configuration

On the target machine, generate the hardware configuration:

```bash
nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Copy this file to `hosts/<hostname>/hardware-configuration.nix`.

### 3. Create Host Configuration

Create `hosts/<hostname>/default.nix`:

```nix
{
  inputs,
  lib,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
    # Device-specific nixos-hardware module (find yours at github.com/NixOS/nixos-hardware)
    inputs.nixos-hardware.nixosModules.<device-module>
    # Optional: Secure boot support
    inputs.lanzaboote.nixosModules.lanzaboote
  ];

  # Host-specific settings
  networking.hostName = "<hostname>";

  # Optional: Secure boot (if using lanzaboote)
  # boot.loader.systemd-boot.enable = lib.mkForce false;
  # boot.lanzaboote = {
  #   enable = true;
  #   pkiBundle = "/var/lib/sbctl";
  # };

  # Device-specific configuration...
}
```

### 4. Create Home-Manager Configuration

Create `hosts/<hostname>/home.nix`:

```nix
{ inputs, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.frank = import ../../home-manager/frank.nix;
    backupFileExtension = "backup";
    sharedModules = [
      inputs.stylix.homeModules.stylix
      inputs.vicinae.homeManagerModules.default
      inputs.niri.homeModules.niri
    ];
    extraSpecialArgs = {
      inherit inputs;
    };
  };
}
```

### 5. Add Host to flake.nix

Add the host definition in `flake.nix`:

```nix
nixosConfigurations = {
  # ... existing hosts ...

  <hostname> = hostLib.mkHost {
    hostname = "<hostname>";
    cpuVendor = "intel";     # or "amd"
    hasFingerprint = false;  # true if device has fingerprint reader
    hasTouchscreen = false;  # true if device has touchscreen
  };
};
```

### 6. Build and Test

```bash
# Test the build (on any machine with Nix)
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel --no-link

# On the target machine, apply the configuration
nh os switch ~/nixos-config
```

## Host Capability Flags

| Flag | Type | Description |
|------|------|-------------|
| `hostname` | string | Host identifier (must match directory name) |
| `cpuVendor` | "amd" \| "intel" | CPU vendor for power management settings |
| `hasFingerprint` | bool | Enable fingerprint authentication |
| `hasTouchscreen` | bool | Enable touch input support (future use) |
| `system` | string | System architecture (default: "x86_64-linux") |

## How Conditional Modules Work

Modules receive `hostConfig` in their arguments and use `lib.mkIf` to conditionally apply configuration:

```nix
{
  lib,
  hostConfig,
  ...
}:
let
  isAmd = hostConfig.cpuVendor == "amd";
in
{
  # Applied to all hosts
  services.power-profiles-daemon.enable = false;

  # Only applied to AMD hosts
  boot.kernelParams = lib.optionals isAmd [ "amd_pstate=guided" ];
}
```

Or wrap the entire module:

```nix
{
  lib,
  hostConfig,
  ...
}:
lib.mkIf (hostConfig.hasFingerprint or false) {
  services.fprintd.enable = true;
  # ... rest of fingerprint config
}
```

## Available nixos-hardware Modules

Common modules for reference:

- **Framework**: `framework-13-amd-7040`, `framework-amd-ai-300-series`
- **Dell Precision**: `dell-precision-5490`, `dell-precision-5530`
- **Microsoft Surface**: `microsoft-surface-common`, `microsoft-surface-pro-9`
- **ThinkPad**: `lenovo-thinkpad-t480`, `lenovo-thinkpad-x1-carbon`

Full list: https://github.com/NixOS/nixos-hardware

## File Structure

```
nixos-config/
├── flake.nix              # Host definitions using mkHost
├── lib/
│   └── hosts.nix          # mkHost helper function
├── hosts/
│   ├── framework/         # Example host
│   │   ├── default.nix    # Host-specific config + nixos-hardware
│   │   ├── hardware-configuration.nix
│   │   └── home.nix       # Home-manager integration
│   └── <new-host>/        # Your new host
│       ├── default.nix
│       ├── hardware-configuration.nix
│       └── home.nix
└── modules/
    └── hardware/
        ├── power-management.nix  # Conditional on cpuVendor
        └── fprintd/              # Conditional on hasFingerprint
```
