# Host Configurations

Machine-specific configurations.

## Directory Structure

```
hosts/
├── framework/              # NixOS (Framework laptop)
│   ├── default.nix         # Host-specific config and overrides
│   ├── hardware-configuration.nix  # Auto-generated hardware config
│   └── home.nix            # Home-manager integration
└── macbook-darwin/         # Darwin (MacBook Pro M4)
    └── default.nix         # All darwin config (system + home-manager)
```

## Host Builders

Hosts are registered in `lib/host-inventory.nix`; `flake.nix` maps that
inventory through `lib/hosts.nix` and `lib/darwin.nix`.

### NixOS (`lib/hosts.nix`)
`mkHost` takes `hostname`, `primaryUser`, `homeDirectory` and the capability
flags (`cpuVendor`, `hasFingerprint`, `hasTouchscreen`, `enableAndroid`,
`enableKeychronM6`, `enableNuphy`, `wifiInterface`, `abmPath`,
`platformProfilePath`).
- Resolves `hosts/<hostname>/default.nix` and `hosts/<hostname>/home.nix`
- Imports `host-options-module.nix` and exposes `hostConfig`
- Applies the NixOS overlays and wires Home Manager with Stylix

### Darwin (`lib/darwin.nix`)
`mkDarwinHost` takes `hostname`, `system`, `primaryUser` and
`homeDirectory`.
- All system config lives in the host's `default.nix` (not `modules/`)
- Sets up Home Manager and applies Darwin-specific overlays
- `hostname` selects the directory; the flake output key comes from the
  inventory attribute name (e.g. `macbook` -> `hosts/macbook-darwin`)

## NixOS Host (Framework)

### hardware-configuration.nix
- **Auto-generated** by `nixos-generate-config`
- **Do NOT manually edit**
- Contains: filesystems, LUKS, kernel modules, hardware detection

### default.nix
Host-specific overrides:
- Hostname, networking
- Hardware-specific settings not in hardware-configuration.nix
- Host-specific packages

### home.nix
Home-manager entry point:
```nix
{ imports = [ ../../home-manager/nixos/frank.nix ]; }
```

## Darwin Host (MacBook)

### default.nix
All-in-one configuration:
- nix-darwin system settings (dock, finder, keyboard, trackpad)
- Homebrew casks for GUI apps
- Touch ID for sudo
- User definition (required for home-manager)
- Home-manager integration

```nix
{
  # System settings
  system.defaults.dock.autohide = true;

  # Homebrew
  homebrew = {
    enable = true;
    casks = [ "jetbrains-toolbox" "ghostty" ];
    onActivation = { cleanup = "zap"; autoUpdate = true; };
  };

  # User (required for home-manager)
  users.users.frank = { name = "frank"; home = "/Users/frank"; };

  # Home-manager
  home-manager.users.frank = import ../../home-manager/darwin/frank.nix;
}
```

## Adding a New Host

### NixOS
1. Create `hosts/<hostname>/`
2. Generate hardware config: `sudo nixos-generate-config --show-hardware-config > hardware-configuration.nix`
3. Create `default.nix` with host-specific settings
4. Create `home.nix` importing user config
5. Add an entry under `nixos` in `lib/host-inventory.nix` (see `docs/new-host.md`)

### Darwin
1. Create `hosts/<hostname>-darwin/default.nix`
2. Configure system defaults, Homebrew, user
3. Add an entry under `darwin` in `lib/host-inventory.nix`

See `docs/new-host.md` for detailed guide.

## Platform Differences

| Aspect | NixOS | Darwin |
|--------|-------|--------|
| System modules | `modules/default.nix` | In host's default.nix |
| State version | `25.05` (string) | `5` (integer) |
| Package manager | nixpkgs only | nixpkgs + Homebrew |
| Init system | systemd | launchd |
| Nix management | NixOS manages | Determinate Systems |
| Home directory | `/home/<user>` | `/Users/<user>` |

## Gotchas

### NixOS
- `hardware-configuration.nix` regenerates on hardware changes
- Host overrides should use `lib.mkForce` if needed
- Secure boot keys in host-specific location
- PSR is force-enabled on Framework via `hardware.amdgpu.dcDebugMask.disablePsr =
  lib.mkForce false` (nixos-hardware defaults it off due to hangs). Rollback:
  restore the default and `amdgpu.dcdebugmask=0x10`; see
  `docs/amdgpu-kworker-io-pressure.md`.
- Framework's additive Umbriel trial uses the already-pinned native module/package;
  Greeter keeps Niri as default. home.nix supplies the pinned upstream Home Manager
  module through extraSpecialArgs: deriving imports from HM config/pkgs directly
  recurses. Keep the existing Niri config, PAM and hardware policy invariant; see
  docs/umbriel-trial.md. Never launch compositors/lock/auth/power tests as agent.
- Framework's pinned CachyOS builder and main nixpkgs can use different module
  certificate formats. Its host overlay selects the provider's aggregateModules
  helper only for CachyOS/provider-stdenv builds; standard kernels retain main's
  helper. Review this when changing the kernel provider. Do not fabricate modules.cer,
  disable signature checks or drop external modules to silence a packaging failure.

### Darwin
- Must set `nix.enable = false` (Determinate Systems manages)
- User definition required for home-manager integration
- Homebrew casks for GUI apps not in nixpkgs
