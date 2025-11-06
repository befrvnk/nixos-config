# Adding a New Host

This guide explains how to add a new machine to your NixOS configuration.

## Prerequisites

- NixOS installed on the new machine
- Git access to this repository
- Basic hardware-configuration.nix generated during installation

## Step-by-Step Process

### 1. Generate Hardware Configuration

On the new machine, generate the hardware configuration:

```bash
nixos-generate-config --show-hardware-config > hardware-configuration.nix
```

### 2. Create Host Directory

In your configuration repository:

```bash
mkdir -p hosts/your-hostname
```

### 3. Copy Hardware Configuration

Copy the `hardware-configuration.nix` from step 1 into your new host directory:

```bash
cp /path/to/hardware-configuration.nix hosts/your-hostname/
```

### 4. Create Host Configuration

Create `hosts/your-hostname/default.nix`:

```nix
{ nixos-hardware, lanzaboote, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules
    # Add hardware-specific modules if needed:
    # nixos-hardware.nixosModules.framework-13-amd
  ];

  # Set hostname
  networking.hostName = "your-hostname";

  # Host-specific configuration
  # (boot settings, hardware tweaks, etc.)
}
```

### 5. Create Overlays Configuration (Optional)

If your host needs custom overlays, create `hosts/your-hostname/overlays.nix`:

```nix
{ android-nixpkgs, niri, ... }:

{
  nixpkgs.overlays = [
    # Add host-specific overlays here
    android-nixpkgs.overlays.default
    (import ../../overlays/niri.nix { inherit niri; })
  ];
}
```

Otherwise, you can skip this file and remove it from the flake imports.

### 6. Create Home-Manager Configuration (Optional)

If this host needs home-manager, create `hosts/your-hostname/home.nix`:

```nix
{ stylix, dankMaterialShell, vicinae, zen-browser, android-nixpkgs, ... }:

{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.frank = import ../../home-manager/frank.nix;
    backupFileExtension = "backup";
    sharedModules = [
      stylix.homeModules.stylix
      dankMaterialShell.homeModules.dankMaterialShell.default
      vicinae.homeManagerModules.default
    ];
    extraSpecialArgs = {
      inherit zen-browser android-nixpkgs;
    };
  };
}
```

Adjust the user name and modules as needed for your new host.

### 7. Update flake.nix

Add your new host to `flake.nix`:

```nix
outputs = { nixpkgs, home-manager, ... }@inputs:
  let
    system = "x86_64-linux";
  in
  {
    nixosConfigurations = {
      framework = nixpkgs.lib.nixosSystem {
        # ... existing framework config
      };

      # Add new host
      your-hostname = nixpkgs.lib.nixosSystem {
        inherit system;
        specialArgs = {
          inherit nixos-hardware lanzaboote inputs;
          inherit stylix dankMaterialShell vicinae zen-browser android-nixpkgs niri;
        };
        modules = [
          ./hosts/your-hostname
          ./hosts/your-hostname/overlays.nix  # Optional
          ./hosts/your-hostname/home.nix      # Optional
          home-manager.nixosModules.home-manager  # If using home-manager
          stylix.nixosModules.stylix              # If using stylix
        ];
      };
    };
  };
```

### 8. Build and Test

Test the configuration builds without errors:

```bash
nix build .#nixosConfigurations.your-hostname.config.system.build.toplevel --no-link
```

### 9. Deploy to New Host

On the new machine, clone your configuration and switch to it:

```bash
# Clone your configuration
git clone <your-repo-url> ~/nixos-config
cd ~/nixos-config

# Build and switch
sudo nixos-rebuild switch --flake .#your-hostname
```

## Host-Specific Customization

### Different User

If the new host uses a different user than "frank", update the home.nix:

```nix
users.yourname = import ../../home-manager/yourname.nix;
```

### Different Modules

Not all hosts need all modules. Customize the imports in `hosts/your-hostname/default.nix`:

```nix
imports = [
  ./hardware-configuration.nix
  ../../modules/system/core.nix
  ../../modules/system/packages.nix
  # Only import modules needed for this host
];
```

### Different Hardware

For specific hardware support, add nixos-hardware modules:

```nix
imports = [
  nixos-hardware.nixosModules.lenovo-thinkpad-t480
  # or
  nixos-hardware.nixosModules.raspberry-pi-4
];
```

## Example: Minimal Server

For a server without desktop environment:

```nix
# hosts/server/default.nix
{ lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../modules/system/core.nix
    ../../modules/system/packages.nix
    ../../modules/services/pipewire.nix  # If needed
  ];

  networking.hostName = "server";

  # Server-specific settings
  services.openssh.enable = true;
  networking.firewall.allowedTCPPorts = [ 22 ];
}
```

Then in flake.nix, only include the needed modules (no home-manager, no stylix for a headless server).

## Tips

- Start with the framework host configuration as a template
- Remove unnecessary modules for your use case
- Test builds locally before deploying
- Keep hardware-configuration.nix in version control
- Document host-specific quirks in comments
