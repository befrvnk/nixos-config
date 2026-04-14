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
├── nushell.nix      # Shell (Nix PATH setup, no Stylix)
├── packages.nix     # CLI packages
├── zed.nix          # Zed editor (Darwin-specific settings)
├── zellij.nix       # Terminal multiplexer
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
2. **Use Homebrew** when a package is unavailable in nixpkgs for aarch64-darwin
3. **Also use Homebrew** for macOS apps that need native self-update behavior (for example, Raycast)

### Before Adding a Package
Always verify the package supports aarch64-darwin:
```bash
# Check if package exists and supported platforms
nix eval nixpkgs#<package>.meta.platforms --json

# Note: nix search can be misleading - packages may appear but not support darwin
```

### User Packages (preferred)
Add to `darwin/packages.nix` for CLI apps and GUI apps that do not need native macOS self-updates:
```nix
home.packages = with pkgs; [
  openchamber
  bat
  fd
];
```

### Homebrew Casks (fallback)
Use when nixpkgs doesn't support aarch64-darwin, or when the app needs native macOS install/update behavior.
Add to `hosts/macbook-darwin/default.nix`:
```nix
homebrew.casks = [ "jetbrains-toolbox" "ghostty" ];
```
Current Homebrew-managed packages/exceptions:
- `1password` - Requires /Applications for security features
- `jetbrains-toolbox` - Not in nixpkgs for Darwin
- `ghostty` - Linux only in nixpkgs
- `miro` - Not in nixpkgs
- `notion` - Needs native macOS self-update support
- `raycast` - Needs native macOS self-update support
- `slack` - Needs native macOS self-update support
- `spotify` - Needs native macOS self-update support

### Shared Packages
Modules in `shared/` (e.g., `shared/worktrunk.nix`) apply to both platforms automatically.

## State Version

Darwin system state version: `5` (integer, not NixOS release number)
Home-manager state version: `25.05`

**Never change these after initial setup.**
