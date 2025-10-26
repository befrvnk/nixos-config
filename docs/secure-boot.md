# Secure Boot with TPM on NixOS

This guide documents the steps to set up Secure Boot with TPM on NixOS, allowing for automatic unlocking of a LUKS-encrypted drive at boot.

## Installation on a New Machine

This configuration cannot be installed directly on a new machine due to a chicken-and-egg problem. The Secure Boot keys need to be created on the target machine before the NixOS configuration can be built, but the keys cannot be created until NixOS is installed.

To install this configuration on a new machine, you need to follow a two-stage process:

1.  **Stage 1: Install NixOS without Secure Boot:** Install a basic NixOS system without the `lanzaboote` and Secure Boot configuration.
2.  **Stage 2: Enable Secure Boot:** After the initial installation, follow the steps in this guide to enable Secure Boot.

## 1. Prerequisites

- A UEFI-based system with a TPM 2.0 module.
- NixOS installed with a LUKS-encrypted root filesystem.
- Secure Boot disabled in the UEFI/BIOS settings for now.

## 2. Create Secure Boot Keys

Before you modify your NixOS configuration, you need to create your own Secure Boot keys:

```bash
nix-shell -p sbctl
sudo sbctl create-keys
```

## 3. Prepare your NixOS Configuration

Next, you need to modify your NixOS configuration to add `lanzaboote` and enable TPM support.

### 3.1. Update `flake.nix`

Add `lanzaboote` to your flake inputs and outputs:

```nix
lanzaboote = {
  url = "github:nix-community/lanzaboote/v0.4.2";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

### 3.2. Update `hosts/framework/default.nix`

Enable `lanzaboote` and disable `systemd-boot`:

```nix
imports = [
  lanzaboote.nixosModules.lanzaboote
];

boot.loader.systemd-boot.enable = lib.mkForce false;
boot.lanzaboote = {
  enable = true;
  pkiBundle = "/var/lib/sbctl";
};
```

### 3.3. Update `modules/system.nix`

Enable TPM2 support and add necessary packages:

```diff
--- a/modules/system.nix
+++ b/modules/system.nix
 { pkgs, ... }:

 {
-  boot.loader.systemd-boot.enable = true;
-  boot.loader.efi.canTouchEfiVariables = true;
+  boot.initrd.systemd.enable = true;
+  security.tpm2.enable = true;

   environment.systemPackages = with pkgs; [
     zsh
+    tpm2-tss
+    sbctl
   ];
```

### 3.4. Update `hosts/framework/hardware-configuration.nix`

Configure your LUKS device to use the TPM:

```diff
--- a/hosts/framework/hardware-configuration.nix
+++ b/hosts/framework/hardware-configuration.nix

-  boot.initrd.luks.devices."luks-3c9a02f2-a630-4164-bf9e-663ff86b4b3d".device = "/dev/disk/by-uuid/3c9a02f2-a630-4164-bf9e-663ff86b4b3d";
+  boot.initrd.luks.devices."luks-3c9a02f2-a630-4164-bf9e-663ff86b4b3d" = {
+    device = "/dev/disk/by-uuid/3c9a02f2-a630-4164-bf9e-663ff86b4b3d";
+    tpm2-device = "auto";
+    allowDiscards = true;
+  };

   fileSystems."/boot" = {
     device = "/dev/disk/by-uuid/9372-F43A";
```

## 4. Rebuild and Reboot

After making these changes, rebuild your NixOS system:

```bash
nixos-rebuild switch --flake .#framework
```

Then, reboot your system.

## 5. Enroll Secure Boot Keys

Now, you need to enroll your own Secure Boot keys.

### 5.1. Enter Setup Mode

On Framework laptops, you can enter setup mode like this:

1.  Select "Administer Secure Boot"
2.  Select "Erase all Secure Boot Settings"

### 5.2. Enroll Keys

```bash
sudo sbctl enroll-keys --microsoft
```

## 6. Enable Secure Boot

On Framework laptops, you may need to manually enable Secure Boot:

1.  Select "Administer Secure Boot"
2.  Enable "Enforce Secure Boot"

## 7. Enroll the TPM Key

Finally, enroll the TPM key with your LUKS-encrypted drive:

```bash
sudo systemd-cryptenroll --tpm2-device=auto --tpm2-pcrs=0+2+7+12 --wipe-slot=tpm2 /dev/nvme0n1p2
```

You will be prompted for the LUKS password to authorize the enrollment.

After this, the system should automatically unlock the encrypted drive at boot without requiring a password.

## Sources
- [Secure Boot & TPM-backed Full Disk Encryption](https://jnsgr.uk/2024/04/nixos-secure-boot-tpm-fde/)
- [Lanzaboote Quickstart Guide](https://github.com/nix-community/lanzaboote/blob/master/docs/QUICK_START.md)
- [Secure Boot with Lanzaboote](https://saylesss88.github.io/installation/enc/lanzaboote.html)
- [Framework and NixOS - Secure Boot](https://0xda.de/blog/2024/06/framework-and-nixos-secure-boot-day-three/)
