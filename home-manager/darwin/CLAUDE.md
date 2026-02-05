# Darwin Home-Manager Configuration

macOS-specific user configuration. No systemd, no Wayland, no Stylix.

## What Goes Here

- Darwin-specific app configs
- Homebrew-managed package configs
- macOS-specific settings
- Packages that need different config than NixOS

## Key Differences from NixOS

| Feature | NixOS | Darwin |
|---------|-------|--------|
| Theming | Stylix + Darkman | Native macOS appearance |
| Services | systemd | launchd (rarely needed) |
| Window manager | niri (Wayland) | Native macOS |
| Shell colors | Base16 injection | System defaults |
| Ghostty package | nixpkgs | Homebrew cask |

## Darwin Gotchas

### Ghostty Package
- **NOT available in nixpkgs for Darwin**
- Must install via Homebrew cask (in `hosts/macbook-darwin/default.nix`)
- Set `programs.ghostty.package = null` in home-manager
- Configuration still managed by home-manager, just not the package
- Use `window-theme = "auto"` to follow system appearance

### No systemd
- Darwin doesn't have systemd
- User services from NixOS don't apply (audio-keep-alive, battery-notifications, etc.)
- macOS equivalents would use launchd, but most aren't needed
- Check services: `launchctl list`, `launchctl print gui/<uid>/<service>`

### Determinate Systems Nix
- Darwin uses Determinate Systems Nix installer
- Set `nix.enable = false` in darwin config (DS manages Nix)
- Don't configure Nix settings in nix-darwin

### Home Directory Path
- macOS: `/Users/frank`
- NixOS: `/home/frank`
- Use `config.home.homeDirectory` in shared modules

### User Definition Required
- nix-darwin requires explicit user definition for home-manager
- Must set in darwin config:
  ```nix
  users.users.frank = { name = "frank"; home = "/Users/frank"; };
  ```

## Theming

Darwin uses native macOS appearance:
- No Stylix or Darkman
- Apps follow system dark/light mode automatically
- No custom wallpaper management (use System Settings)
- No Catppuccin/base16 color injection
- GTK apps (if any) may need manual dark mode config

### Ghostty Theme
```nix
programs.ghostty.settings = {
  window-theme = "auto";  # Follows system appearance
};
```

## Module Organization

```
darwin/
├── frank.nix        # Main config - imports shared + darwin modules
├── ghostty.nix      # Terminal (Homebrew package, no Stylix)
├── nushell.nix      # Shell (no Stylix theming)
├── packages.nix     # CLI packages
└── zen-browser.nix  # Browser with extension policies
```

### Importing Shared Modules
```nix
# darwin/frank.nix
imports = [
  ../shared/atuin.nix
  ../shared/git.nix
  ../shared/starship.nix
  ../shared/ssh.nix
  ./ghostty.nix
  ./nushell.nix
  ./packages.nix
];
```

## Adding Packages

### Package Source Priority
1. **Prefer nixpkgs** for version pinning and reproducibility
2. **Use Homebrew** only when package is unavailable in nixpkgs for aarch64-darwin

### Before Adding a Package
Always verify the package supports aarch64-darwin:
```bash
# Check if package exists and supported platforms
nix eval nixpkgs#<package>.meta.platforms --json

# Note: nix search can be misleading - packages may appear but not support darwin
```

### User Packages (preferred)
Add to `darwin/packages.nix` for GUI and CLI apps:
```nix
home.packages = with pkgs; [
  notion-app  # Note: notion-app, not notion (which is a window manager)
  slack
];
```

### Homebrew Casks (fallback)
Only use when nixpkgs doesn't support aarch64-darwin.
Add to `hosts/macbook-darwin/default.nix`:
```nix
homebrew.casks = [ "jetbrains-toolbox" "ghostty" ];
```
Current Homebrew-only packages:
- `1password` - Requires /Applications for security features
- `jetbrains-toolbox` - Not in nixpkgs for Darwin
- `ghostty` - Linux only in nixpkgs
- `miro` - Not in nixpkgs

### Shared Packages
Modules in `shared/` (e.g., `shared/worktrunk.nix`) apply to both platforms automatically.

## State Version

Darwin system state version: `5` (integer, not NixOS release number)
Home-manager state version: `25.05`

**Never change these after initial setup.**
