# NixOS System Configurations
This repository contains my NixOS system configurations.

## Documentation

- [Repository Structure](./docs/structure.md) - Overview of the configuration organization
- [Adding Packages](./docs/adding-packages.md) - Guide for adding system and user packages
- [Adding a New Host](./docs/new-host.md) - How to configure additional machines
- [Secure Boot with TPM](./docs/secure-boot.md) - Secure boot setup guide
- [Stylix & Darkman Setup](./docs/stylix-darkman-setup.md) - Theme switching configuration
- [Development Environment](./docs/development-environment.md) - Automatic formatting and dev shell setup

## Hardware

*   **Laptop:** Framework 13, Ryzen AI 9 HX 370, US (ANSI) keyboard layout, 2x32GB DDR5-5600, 1TB WD_BLACK SN850X NVMe - M.2 2280
*   **Keyboard:** Nuphy Air75 V3
*   **Mouse:** Logitech G403
*   **Monitor:** Dough Spectrum 4k 144Hz 27 inch

## TODOs

System
- Fix login manager
- Configure fingerprint sensor
- Remove GNOME

Hardware
- Fix Nuphy function keys
- Fix wakeup from closed screen

Android
- Switch to flake setup

Zed
- Disable tabs

Documentation
- List all packages and apps
- Add readme for `rebuild switch`
- Language documentation
- App and WM shortcuts

Repository
- Update bot for flakes

## Updating Flakes

To update all flakes and their dependencies, run the following command:

```bash
nix flake update
```
