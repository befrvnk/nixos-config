# Adding a New Host

This repo builds hosts through the helpers in:
- `lib/hosts.nix` for NixOS
- `lib/darwin.nix` for nix-darwin

Host-specific files live under `hosts/`.

## NixOS Host

### 1. Create the host directory

```bash
mkdir -p hosts/<hostname>
```

### 2. Generate hardware configuration

On the target machine:

```bash
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Copy that file into:

```text
hosts/<hostname>/hardware-configuration.nix
```

### 3. Create `hosts/<hostname>/default.nix`

Start from the existing Framework host and keep only what the new machine needs.

Minimal shape:

```nix
{
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ../../modules
  ];

  networking.hostName = "<hostname>";
}
```

### 4. Create `hosts/<hostname>/home.nix`

```nix
{
  inputs,
  hostConfig,
  ...
}:
{
  home-manager = {
    backupFileExtension = "hm-backup";
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${hostConfig.primaryUser} = ../../home-manager/nixos/frank.nix;
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

### 5. Add the host to `flake.nix`

```nix
nixosConfigurations.<hostname> = hostLib.mkHost {
  hostname = "<hostname>";
  primaryUser = "frank";
  homeDirectory = "/home/frank";
  cpuVendor = "intel";      # or "amd"
  hasFingerprint = false;
  hasTouchscreen = false;
  enableAndroid = false;
  enableLogitech = false;
  enableNuphy = false;
  wifiInterface = null;       # set if power-management scripts should manage WiFi power save
  abmPath = null;             # set on AMD laptops with panel power savings support
};
```

### 6. Build and test

```bash
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel --dry-run --accept-flake-config
nh os test .
```

## Darwin Host

### 1. Create the host directory

```bash
mkdir -p hosts/<hostname>-darwin
```

### 2. Create `hosts/<hostname>-darwin/default.nix`

Start from `hosts/macbook-darwin/default.nix` and trim what you do not need.

### 3. Add the host to `flake.nix`

```nix
darwinConfigurations.<hostname> = darwinLib.mkDarwinHost {
  hostname = "<hostname>-darwin";
  primaryUser = "frank";
  homeDirectory = "/Users/frank";
};
```

### 4. Build and test

```bash
nix build .#darwinConfigurations.<hostname>.system --dry-run --accept-flake-config
```

## Host Metadata

`mkHost` and `mkDarwinHost` pass `hostConfig` into modules. Use that for host-specific values instead of hardcoding them in modules.

Common fields include:
- `hostConfig.hostname`
- `hostConfig.system`
- `hostConfig.primaryUser`
- `hostConfig.homeDirectory`
- `hostConfig.cpuVendor`
- `hostConfig.hasFingerprint`
- `hostConfig.hasTouchscreen`

NixOS hosts can also set capability flags like:
- `enableAndroid`
- `enableLogitech`
- `enableNuphy`
- `wifiInterface`
- `abmPath`
- `platformProfilePath`

## Notes

- `lib/hosts.nix` validates host paths and a few required fields
- keep host-specific quirks inside `hosts/<hostname>/`
- avoid hardcoding usernames or home directories in reusable modules
- for more structure guidance, see `docs/structure.md`
