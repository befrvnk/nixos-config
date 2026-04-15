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

Located in `lib/`:

### NixOS (`lib/hosts.nix`)
```nix
mkHost = { hostname, system ? "x86_64-linux", extraModules ? [] }:
```
- Imports `modules/default.nix` (all system modules)
- Sets up home-manager integration
- Applies overlays

### Darwin (`lib/darwin.nix`)
```nix
mkDarwinHost = { hostname, system ? "aarch64-darwin", extraModules ? [] }:
```
- All system config in host's `default.nix` (not modules/)
- Sets up home-manager integration
- Applies darwin-specific overlays

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
5. Add to `flake.nix`:
   ```nix
   nixosConfigurations.<hostname> = mkHost { hostname = "<hostname>"; };
   ```

### Darwin
1. Create `hosts/<hostname>-darwin/default.nix`
2. Configure system defaults, Homebrew, user
3. Add to `flake.nix`:
   ```nix
   darwinConfigurations.<hostname> = mkDarwinHost { hostname = "<hostname>"; };
   ```

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

### Darwin
- Must set `nix.enable = false` (Determinate Systems manages)
- User definition required for home-manager integration
- Homebrew casks for GUI apps not in nixpkgs
