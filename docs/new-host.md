# Adding a New Host

Hosts are built through:
- `lib/hosts.nix` for NixOS (`mkHost`)
- `lib/darwin.nix` for nix-darwin (`mkDarwinHost`)

The flake does not contain a per-host literal. It maps
`lib/host-inventory.nix` through those builders, so **registering a host means
adding an entry to the inventory**, not editing `flake.nix`.

## NixOS Host

### 1. Create the host directory

```bash
mkdir -p hosts/<hostname>
```

### 2. Generate the hardware configuration

On the target machine:

```bash
sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

Copy it to:

```text
hosts/<hostname>/hardware-configuration.nix
```

### 3. Create `hosts/<hostname>/default.nix`

Start from `hosts/framework/default.nix` and keep only what the machine needs.

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

`mkHost` requires this file. Copy `hosts/framework/home.nix` and adjust the
user/import paths:

```nix
{ inputs, hostConfig, ... }:
{
  home-manager = {
    backupFileExtension = "hm-backup";
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${hostConfig.primaryUser}.imports = [
      ../../home-manager/nixos/frank.nix
    ];
    sharedModules = [
      inputs.stylix.homeModules.stylix
      inputs.vicinae.homeManagerModules.default
      inputs.niri.homeModules.niri
      # Keep Stylix from defining Home Manager-local overlays that are ignored
      # with useGlobalPkgs.
      { stylix.overlays.enable = false; }
    ];
    extraSpecialArgs = {
      inherit inputs hostConfig;
    };
  };
}
```

Desktop-specific modules (Noctalia, Niri, Zen Browser, Umbriel) live in
`home-manager/nixos/frank.nix` or the host's own `home.nix`; a headless host
should import only what it needs.

### 5. Register the host in `lib/host-inventory.nix`

Add an entry under `nixos`:

```nix
nixos = {
  framework = { ... };
  <hostname> = {
    hostname = "<hostname>";
    primaryUser = "frank";
    homeDirectory = "/home/frank";
    cpuVendor = "intel";        # or "amd"
    hasFingerprint = false;
    hasTouchscreen = false;
    enableAndroid = false;
    enableKeychronM6 = false;
    enableNuphy = false;
    wifiInterface = null;       # if power-management manages WiFi power save
    abmPath = null;             # AMD panels with ABM support
    platformProfilePath = "/sys/firmware/acpi/platform_profile"; # omit for this default
  };
};
```

The attribute name becomes `nixosConfigurations.<hostname>`; `mkHost` derives
`hosts/<hostname>` and `hosts/<hostname>/home.nix` from `hostname` and fails
evaluation if either is missing.

### 6. Build and test

```bash
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel \
  --dry-run --accept-flake-config
nh os build .
```

Switch only after the dry run and a full build succeed.

## Darwin Host

### 1. Create the host directory

Use the `-darwin` suffix, matching the existing `hosts/macbook-darwin`:

```bash
mkdir -p hosts/<name>-darwin
```

### 2. Create `hosts/<name>-darwin/default.nix`

Start from `hosts/macbook-darwin/default.nix` and trim what is not needed.
The Darwin builder does not require a `home.nix`; Home Manager is wired inside
the host file.

### 3. Register the host in `lib/host-inventory.nix`

Add an entry under `darwin`:

```nix
darwin = {
  macbook = {
    hostname = "macbook-darwin";
    primaryUser = "frank";
    homeDirectory = "/Users/frank";
  };
  <name> = {
    hostname = "<name>-darwin";
    primaryUser = "frank";
    homeDirectory = "/Users/frank";
  };
};
```

The attribute name becomes `darwinConfigurations.<name>`; `hostname` selects the
`hosts/<hostname>` directory. The two intentionally differ for `macbook`.

### 4. Build and test

```bash
nix build .#darwinConfigurations.<name>.system --dry-run --accept-flake-config
```

## Special Case: hermi

`hosts/hermi` is not in the inventory. It is added directly in `flake.nix`
because it must use `nixos-raspberrypi.lib.nixosSystem` and its own pinned
nixpkgs. Keep that override local to the flake and follow
`docs/hermi-raspberry-pi-setup.md` when changing it.

## Host Metadata

`mkHost` and `mkDarwinHost` pass `hostConfig` into every module. Use it instead
of hardcoding machine values inside reusable modules:

- `hostConfig.hostname`
- `hostConfig.system`
- `hostConfig.primaryUser`
- `hostConfig.homeDirectory`
- `hostConfig.cpuVendor`
- `hostConfig.hasFingerprint`
- `hostConfig.hasTouchscreen`

NixOS hosts can also set:
- `enableAndroid`
- `enableKeychronM6`
- `enableNuphy`
- `wifiInterface`
- `abmPath`
- `platformProfilePath`

## Notes

- `lib/hosts.nix` validates the host path, `home.nix`, CPU vendor and absolute
  home directory, and throws at evaluation time with a readable message.
- Keep host-specific quirks in `hosts/<hostname>/`.
- Avoid hardcoding usernames or home directories in reusable modules.
- See `docs/structure.md` for the overall layout.
