# NixOS System Configurations

This repository contains my personal NixOS system configurations for a Framework 13 laptop with Niri window manager.

## Quick Start

- **Rebuild system:** `sudo nixos-rebuild switch --flake .#hostname`
- **Update flakes:** `nix flake update`
- **Format Nix files:** `nix develop -c nixfmt **/*.nix flake.nix`

## Documentation

- [Repository Structure](./docs/structure.md) - Overview of the configuration organization
- [Adding Packages](./docs/adding-packages.md) - Guide for adding system and user packages
- [Adding a New Host](./docs/new-host.md) - How to configure additional machines
- [Secure Boot with TPM](./docs/secure-boot.md) - Secure boot setup guide
- [Stylix & Darkman Setup](./docs/stylix-darkman-setup.md) - Theme switching configuration
- [Development Environment](./docs/development-environment.md) - Automatic formatting and dev shell setup

## Hardware

- **Laptop:** Framework 13, Ryzen AI 9 HX 370, US (ANSI) keyboard layout, 2x32GB DDR5-5600, 1TB WD_BLACK SN850X NVMe - M.2 2280
- **Keyboard:** Nuphy Air75 V3
- **Mouse:** Logitech G403
- **Monitor:** Dough Spectrum 4k 144Hz 27 inch

## TODOs

### System Configuration

- **Configure fingerprint sensor support** - Set up fingerprint authentication for the Framework 13 laptop using fprintd and PAM integration
- **Remove GNOME packages and services** - GNOME is being replaced by Niri window manager. Ensure the login manager configuration is updated to use the appropriate display manager for Niri

### Hardware Issues

- **Fix Nuphy Air75 V3 function keys** - Function keys (volume control, brightness adjustment) are not working. Investigate keyboard firmware settings and NixOS keyboard configuration
- **Fix Shift+Enter terminal behavior** - Pressing Shift+Enter in terminals outputs `;2;13~` instead of creating a new line. This affects Claude CLI but not Gemini CLI. Investigate terminal keybinding configuration (likely in Ghostty config)
- **Fix USB-C monitor wake-from-sleep** - When the Framework laptop is closed and connected to external monitor via USB-C, the system cannot wake up even though external monitor, keyboard, and mouse are connected. Investigate power management and display configuration settings

### Development Environment

- **Migrate to Android development flake** - Switch from using the nixos unstable channel for Android development tools to using a dedicated Android flake for better version control and reproducibility

### Application Configuration

- **Disable Zed tab bar UI** - Configure Zed editor to hide the tab bar interface completely

### Documentation

- **Add packages and applications list** - Create a comprehensive section in this README listing all installed system packages and applications
- **Document rebuild switch command** - Add detailed documentation explaining how to use `nixos-rebuild switch` with this flake-based configuration
- **Add Nix language primer** - Document key Nix language concepts and patterns used in this repository to make it accessible for beginners
- **Document keyboard shortcuts** - Create a comprehensive guide for configured keyboard shortcuts across applications and the Niri window manager

### Repository Automation

- **Set up Renovate bot** - Configure Renovate to automatically create pull requests for updates to packages in the `flake.lock` file

## Proposed Documentation Structure

The following is a proposed structure for comprehensive usage documentation to be created in the future:

### Terminal
- Direnv usage and configuration
- Starship prompt customization
- Common commands reference

### Applications
- **Zen Browser**
  - Installed addons and extensions
- **Zed**
  - Configuration and shortcuts
- **Ghostty**
  - Terminal configuration

### Window Manager (Niri)
- Waybar (topbar) configuration
- Vicinae setup
- Niri configuration details
- Keyboard shortcuts
- Floating window rules
