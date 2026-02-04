# Home-Manager Configuration

User-level configurations organized by platform.

## Directory Structure

```
home-manager/
├── nixos/             # NixOS-specific modules
│   ├── frank.nix      # Main config (imports all NixOS modules)
│   ├── niri/          # Window manager (Wayland)
│   ├── ironbar/       # Status bar
│   ├── darkman/       # Theme switching
│   ├── stylix.nix     # Theming with specializations
│   └── */             # Other NixOS-specific configs
├── darwin/            # Darwin-specific modules
│   ├── frank.nix      # Main config (imports shared + darwin modules)
│   ├── ghostty.nix    # Terminal (Homebrew package)
│   ├── nushell.nix    # Shell (no Stylix)
│   ├── packages.nix   # CLI packages
│   └── zen-browser.nix
└── shared/            # Cross-platform modules
    ├── atuin.nix      # Shell history
    ├── git.nix        # Version control
    ├── starship.nix   # Prompt
    ├── ssh.nix        # SSH config
    └── */             # Other shared configs
```

## Platform Decision Criteria

**Shared module** (put in `shared/`):
- Pure CLI configuration
- No systemd services
- No Wayland/X11 dependencies
- No Stylix color injection

**NixOS-only** (put in `nixos/`):
- Uses systemd services
- Uses Wayland/compositor features
- Uses `config.lib.stylix.colors`
- Desktop environment components

**Darwin-only** (put in `darwin/`):
- macOS-specific settings
- Homebrew-managed packages
- launchd services (rare)

## Adding New Modules

### Simple Module (single file)
1. Create `home-manager/<platform>/app.nix`
2. Import in `frank.nix`:
   ```nix
   imports = [ ./app.nix ];
   ```

### Complex Module (directory)
1. Create directory:
   ```
   home-manager/<platform>/app/
   ├── default.nix    # Entry point
   ├── config.yaml    # Config files
   └── script.sh      # Scripts
   ```
2. Import in `frank.nix`: `imports = [ ./app ];`

### Modular Splitting Pattern
For complex configs, split by concern:
```nix
# default.nix
{ lib, ... }:
{
  imports = [ ./binds.nix ./layout.nix ./rules.nix ];
  programs.app.settings = lib.mkMerge [ /* merged from imports */ ];
}
```
Examples: `nixos/niri/`, `nixos/ironbar/`

## Configuration Patterns

### Script Embedding
```nix
let
  myScript = pkgs.writeShellScript "name" ''
    export PATH="${pkgs.foo}/bin:${pkgs.bar}/bin:$PATH"
    ${builtins.readFile ./script.sh}
  '';
in {
  systemd.user.services.my-service.Service.ExecStart = "${myScript}";
}
```

Or with variable replacement:
```nix
home.file.".local/share/script.sh" = {
  source = pkgs.replaceVars ./script.sh {
    tool = "${pkgs.tool}";
  };
  executable = true;
};
```

### Creating User Services (NixOS)
```nix
systemd.user.services.my-service = {
  Unit = {
    Description = "My service";
    After = [ "graphical-session.target" ];
    PartOf = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${myScript}";
    Restart = "on-failure";
    RestartSec = "5";
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```
Check status: `systemctl --user status my-service`

### Event Monitoring Service Pattern
For services watching system events:
```nix
let
  watcherScript = pkgs.writeShellScript "watcher" ''
    udevadm monitor --udev --subsystem-match=drm | while read -r line; do
      if echo "$line" | grep -q "change"; then
        sleep 2  # Debounce
        some-action
      fi
    done
  '';
in { /* service definition */ }
```
Used in: `nixos/darkman/` (monitor-hotplug), `nixos/ironbar/modules/niri-overview-watcher/`

## Adding Packages

**NixOS user packages:**
- If module exists (e.g., `shared/worktrunk.nix`), add `home.packages` there
- Otherwise add to `nixos/packages.nix`

**Darwin user packages:**
- CLI tools: `darwin/packages.nix`
- Shared modules apply automatically

## Shared Resources

### Theme Definitions (`shared/themes.nix`)
Single source of truth for both platforms:
```nix
{ pkgs }:
{
  dark = parseScheme "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
  light = parseScheme "${pkgs.base16-schemes}/share/themes/catppuccin-latte.yaml";
}
```

**Imported by (NixOS):** stylix.nix, ghostty.nix, nushell.nix, zen-browser/

### Wallpapers (`wallpapers/default.nix`)
```nix
{ light = ./mountain.jpg; dark = ./mountain_dark.jpg; }
```
**Imported by:** stylix.nix, darkman/
