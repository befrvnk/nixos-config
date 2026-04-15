# Multi-Host Configuration

This repo supports multiple hosts, but the source of truth is now split across a few specific files:

- `lib/host-inventory.nix` - host data
- `lib/hosts.nix` - NixOS builder
- `lib/darwin.nix` - Darwin builder
- `lib/host-options-module.nix` - typed host metadata exposed as `config.my.host`

## Canonical References

- For adding a new machine: see [Adding a New Host](./new-host.md)
- For repository layout: see [Repository Structure](./structure.md)

This document focuses only on the shared host model.

## Host Inventory

`flake.nix` no longer hand-writes each system directly. Instead, it imports `lib/host-inventory.nix` and generates:

- `nixosConfigurations`
- `darwinConfigurations`

Each inventory entry contains the metadata needed by the relevant host builder.

## Host Metadata

Host metadata is exposed through typed module options at:

- `config.my.host`

A compatibility alias is also provided as the module argument:

- `hostConfig`

That means reusable modules can depend on explicit host metadata without each builder passing around an ad-hoc attrset.

Common fields include:
- `hostname`
- `system`
- `primaryUser`
- `homeDirectory`
- `cpuVendor`
- `hasFingerprint`
- `hasTouchscreen`

NixOS hosts may also define capability flags such as:
- `enableAndroid`
- `enableLogitech`
- `enableNuphy`
- `wifiInterface`
- `abmPath`
- `platformProfilePath`

## Profiles

The NixOS module stack is now split into profiles:

- `modules/profiles/base.nix`
- `modules/profiles/desktop.nix`
- `modules/profiles/framework.nix`

This keeps `modules/default.nix` small and makes host-specific hardware imports more explicit.

## Conditional Module Pattern

Reusable modules should read host metadata and gate behavior with `lib.mkIf`.

Example:

```nix
{
  lib,
  hostConfig,
  ...
}:
lib.mkIf (hostConfig.hasFingerprint or false) {
  services.fprintd.enable = true;
}
```

For modules that need richer metadata, prefer fields under `config.my.host` / `hostConfig` rather than hardcoding usernames, paths, or interfaces.
