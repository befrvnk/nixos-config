# MacBook VM Setup Guide

This guide covers setting up a two-layer NixOS development environment on a MacBook with Apple Silicon:

1. **macOS host** - Managed by nix-darwin (installs UTM, dev tools, shell config)
2. **NixOS VM guest** - Runs the full desktop environment (Niri, Ironbar, etc.)

## Target Hardware

- MacBook Pro 14" (2024) - Apple M4 Pro, 48GB RAM
- Any Apple Silicon Mac should work with minor adjustments

## Prerequisites

- macOS Sonoma or later
- Internet connection
- Admin access

## Phase 1: Install Nix on macOS

Install Nix using the Determinate Systems installer (recommended for macOS):

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```

Restart your terminal or source the profile:

```bash
. /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

Verify installation:

```bash
nix --version
```

## Phase 2: Clone and Apply Darwin Configuration

Clone the repository:

```bash
git clone https://github.com/your-username/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

First-time nix-darwin bootstrap:

```bash
nix run nix-darwin -- switch --flake .#macbook
```

For subsequent rebuilds:

```bash
darwin-rebuild switch --flake .#macbook
```

This installs:
- UTM (via Homebrew cask)
- Git, vim, wget, curl
- Zsh with Nix paths configured
- Touch ID for sudo

## Phase 3: Create NixOS VM in UTM

1. Download NixOS ISO (aarch64/ARM64 version) from https://nixos.org/download
2. Open UTM (installed by nix-darwin in Phase 2)
3. Create new VM with these settings:
   - **Type**: Linux
   - **Architecture**: ARM64 (aarch64)
   - **RAM**: 16-24GB (you have plenty with 48GB)
   - **CPU**: 8+ cores
   - **Disk**: 128GB
   - **Display**: virtio-gpu-pci
   - **Network**: Shared Network (or Bridged for SSH access)
4. Boot from NixOS ISO

## Phase 4: Install NixOS in VM

In the VM, open a terminal and become root:

```bash
sudo -i
```

Partition the disk:

```bash
parted /dev/vda -- mklabel gpt
parted /dev/vda -- mkpart boot fat32 1MB 512MB
parted /dev/vda -- set 1 esp on
parted /dev/vda -- mkpart root ext4 512MB 100%
```

Format partitions:

```bash
mkfs.fat -F32 -n boot /dev/vda1
mkfs.ext4 -L nixos /dev/vda2
```

Mount filesystems:

```bash
mount /dev/disk/by-label/nixos /mnt
mkdir -p /mnt/boot
mount /dev/disk/by-label/boot /mnt/boot
```

Generate initial config:

```bash
nixos-generate-config --root /mnt
```

Install minimal system:

```bash
nixos-install --no-root-passwd
```

Reboot and remove the ISO from UTM:

```bash
reboot
```

## Phase 5: Apply Full Configuration in VM

After rebooting, login as root (no password required initially).

Set password for frank user:

```bash
passwd frank
```

Switch to frank user:

```bash
su - frank
```

Clone the config:

```bash
git clone https://github.com/your-username/nixos-config.git ~/nixos-config
cd ~/nixos-config
```

Apply the configuration:

```bash
sudo nixos-rebuild switch --flake .#macbook-vm
```

Reboot to apply all changes:

```bash
sudo reboot
```

## Phase 6: Post-Installation

### Display Resize

The SPICE agent should auto-resize the display. If not, use `wlr-randr` or Niri's output settings.

### Shared Folders

Configure in UTM settings > Sharing if you need to share files between host and guest.

### SSH Access

From macOS host:

```bash
ssh frank@<vm-ip>
```

Find the VM's IP with `ip addr` in the VM.

## Troubleshooting

### "Hardware not supported" errors

The VM config disables hardware-specific features via `isVirtualMachine = true`. If errors persist, check `journalctl -b` for specific module failures.

### Graphics issues

Software rendering is forced via `LIBGL_ALWAYS_SOFTWARE=1`. Performance will be slower than native but functional for development.

### Network not working

Try switching between "Shared Network" and "Bridged" in UTM settings. Check `ip addr` in VM to verify interface is up.

### Build failures

If the NixOS VM build fails, ensure you're building for the correct architecture:

```bash
nix build .#nixosConfigurations.macbook-vm.config.system.build.toplevel --dry-run
```

## Configuration Details

### Darwin Host (`hosts/macbook-darwin/`)

- Homebrew for UTM (cask)
- Zsh with Nix daemon paths
- Touch ID for sudo
- Basic system packages

### NixOS VM (`hosts/macbook-vm/`)

- QEMU guest profile with virtio drivers
- SPICE agent for clipboard/resize
- Software rendering fallback
- SSH enabled for host access
- TPM2 disabled (via `isVirtualMachine` flag)
- Lid handling disabled (via `isVirtualMachine` flag)
- Power management (tuned) disabled (via `isVirtualMachine` flag)

### Shared Configuration

Both hosts use the same home-manager configuration (`home-manager/frank.nix`), so your development environment is consistent.
