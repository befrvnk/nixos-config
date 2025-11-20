# NixOS Configuration Agent Guidelines

## Build & Test Commands
- **Build system:** `nh os switch ~/nixos-config` (uses [nh](https://github.com/nix-community/nh) for better output)
- **Test configuration:** `nix build .#nixosConfigurations.framework.config.system.build.toplevel --dry-run`
- **Check flake:** `nix flake check`
- **Format code:** `nix fmt -- --check .` (auto-formatted on commit via pre-commit hooks)
- **Update flakes:** `nix flake update`

## Code Style Guidelines
- **Formatting:** Uses `nixfmt-rfc-style` - automatically applied via pre-commit hooks
- **File structure:** Modular organization with clear separation (modules/, home-manager/, hosts/)
- **Imports:** Use relative imports within modules, absolute paths for cross-module imports
- **Naming:** kebab-case for files, camelCase for variables where appropriate
- **Comments:** Minimal inline comments, prefer self-documenting code
- **Error handling:** Use proper Nix attribute set validation and default values

## Development Workflow
- direnv automatically loads dev shell on directory entry
- Pre-commit hooks ensure all committed code is formatted
- Use `rebuild` function from zsh for convenient system rebuilding
- Test changes with dry-run builds before applying

## Project Structure

### Directory Organization
```
nixos-config/
├── flake.nix              # Entry point - inputs, outputs, overlays
├── hosts/                 # Host-specific configurations
│   └── framework/         # Framework laptop config
│       ├── default.nix    # Host config
│       ├── hardware-configuration.nix  # Auto-generated
│       └── home.nix       # Home-manager integration
├── modules/               # System-level NixOS modules
│   ├── default.nix        # Central import file
│   ├── users.nix          # User account definitions
│   ├── desktop/           # Display manager, compositor
│   ├── hardware/          # Hardware-specific (fprintd, power, keyboard)
│   ├── services/          # System services (darkman, pipewire, bluetooth)
│   ├── system/            # Core settings (boot, networking, packages)
│   └── theming/           # System-level stylix config
├── home-manager/          # User-level configurations
│   ├── frank.nix          # Main user config (imports all)
│   ├── packages.nix       # User application packages
│   ├── stylix.nix         # Theming with specializations
│   ├── niri/              # Window manager (split by concern)
│   ├── ironbar/           # Status bar (modular scripts)
│   └── */                 # Other app configs
├── overlays/              # Package modifications
└── docs/                  # Detailed documentation
```

### Module Import Patterns

**System modules:** `modules/default.nix` acts as central import point
- Each host imports this single file
- Organized by category: core, users, system, hardware, desktop, services, theming

**Home-Manager modules:** `home-manager/frank.nix` imports all user modules
- Complex apps get directories (niri/, ironbar/, darkman/)
- Simple configs are single files (git.nix, ssh.nix, zsh.nix)
- Each module is self-contained

## System vs Home-Manager Split

**System Level** (`modules/`): Root-level, affects all users
- Boot configuration (LUKS, TPM2, secure boot)
- Hardware drivers and firmware
- System services (greetd, darkman daemon, pipewire)
- Network management, power management
- Security (PAM, polkit, TPM)
- System users and groups

**Home-Manager Level** (`home-manager/`): User-specific customization
- User applications and packages
- Shell configuration (zsh, starship)
- Application settings (git, ssh, editors)
- Window manager keybindings and rules
- Desktop environment (ironbar, vicinae, dunst)
- User services (swayidle, battery notifications)
- Theming specializations (dark/light modes)

**Package Split:**
- System packages: `modules/system/packages.nix` (git, vim, wget, core tools)
- User packages: `home-manager/packages.nix` (GUI apps, dev tools, CLI tools)

## Common Configuration Patterns

### Script Embedding Pattern
Scripts are embedded using `pkgs.writeShellScript`:
```nix
let
  myScript = pkgs.writeShellScript "script-name" ''
    export PATH="${pkgs.foo}/bin:${pkgs.bar}/bin:$PATH"
    ${builtins.readFile ./script.sh}
  '';
in
{
  systemd.user.services.my-service = {
    Service.ExecStart = "${myScript}";
  };
}
```

Or with variable replacement:
```nix
home.file.".local/share/script.sh" = {
  source = pkgs.replaceVars ./script.sh {
    tool = "${pkgs.tool}";
    path = "${some.path}";
  };
  executable = true;
};
```

### Stylix Color Injection Pattern
Access Stylix colors via `config.lib.stylix.colors`:
```nix
{ config, ... }:
let
  colors = config.lib.stylix.colors;
in
{
  # Example: Generate CSS with color variables
  xdg.configFile."app/style.css".text = ''
    @define-color base00 #${colors.base00};
    @define-color base01 #${colors.base01};
  '';
}
```

Used in: `ironbar/default.nix`, `niri/layout.nix`

### Modular Splitting by Concern
Complex configurations split into multiple files:
```nix
# default.nix - Entry point
{ lib, ... }:
{
  imports = [
    ./binds.nix
    ./layout.nix
    ./rules.nix
  ];

  programs.app.settings = lib.mkMerge [
    # Settings from imported modules merge here
  ];
}
```

Examples: `home-manager/niri/`, `home-manager/ironbar/`

### Specialization Pattern (Theme Switching)
Enable theme switching without full rebuilds:
```nix
{
  stylix = { ... };  # Base configuration

  specialisation = {
    dark.configuration = {
      stylix.polarity = lib.mkForce "dark";
      stylix.base16Scheme = lib.mkForce "catppuccin-mocha";
    };
    light.configuration = {
      stylix.polarity = lib.mkForce "light";
      stylix.base16Scheme = lib.mkForce "catppuccin-latte";
    };
  };
}
```

See: `home-manager/stylix.nix`

### Shared Resource Pattern
Define shared resources once, import everywhere:
```nix
# home-manager/wallpapers/default.nix
{
  light = ./mountain.jpg;
  dark = ./mountain_dark.jpg;
}
```

Imported in: `stylix.nix`, `darkman/default.nix`

## Adding New Modules

### Simple Module (single file)
1. Create `home-manager/new-app.nix` or `modules/category/new-app.nix`
2. Import in `frank.nix` or `modules/default.nix`:
   ```nix
   imports = [ ./new-app.nix ];
   ```

### Complex Module (directory)
1. Create directory structure:
   ```
   home-manager/new-app/
   ├── default.nix        # Entry point
   ├── config.yaml        # Config files
   └── script.sh          # Scripts
   ```
2. Import in `frank.nix`: `imports = [ ./new-app ];`

### Adding Packages
- **System package:** Add to `modules/system/packages.nix`
- **User package:** Add to `home-manager/packages.nix`
- **Custom package:** Create overlay in `overlays/`

### Creating User Services
```nix
systemd.user.services.my-service = {
  Unit = {
    Description = "My service";
    After = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${myScript}";
    Restart = "always";
    RestartSec = "10";
  };
  Install = {
    WantedBy = [ "graphical-session.target" ];
  };
};
```

## Security Considerations

### PAM Configuration Pattern
Fingerprint authentication uses structured PAM rules:
```nix
security.pam.services.sudo = {
  rules.auth.fprintd = {
    order = 11400;  # Before unix auth (12000)
    control = "sufficient";
    modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
    args = ["timeout=10" "max-tries=3"];
  };
};
```

Applied to: sudo, login, greetd, swaylock, polkit-1

See: `modules/hardware/fprintd/default.nix`

### Keyring Management
- gnome-keyring is managed by PAM in `modules/desktop/greetd.nix`
- **Do NOT enable** `services.gnome-keyring.enable` in home-manager
- Use `lib.mkForce false` to override defaults

### Secure Boot & Encryption
- Lanzaboote handles secure boot integration
- LUKS with TPM2 auto-unlock configured in `hardware-configuration.nix`
- 1Password integration via polkit

## Theming System

### Three-Layer Architecture
1. **System-level Stylix** (`modules/theming/stylix.nix`): Minimal base config
2. **Home-Manager Stylix** (`home-manager/stylix.nix`): Full theming with specializations
3. **Darkman Integration**: Time-based light/dark switching

### Wallpaper Management (awww)
- awww-daemon runs continuously (started in `niri/startup.nix`)
- Darkman sends `awww img` command on theme change
- 1-second fade transitions between wallpapers
- Placed on backdrop layer (visible in Niri overview mode)

### Theme Switching
Darkman script (`darkman-switch-mode.sh`) handles:
- Systemd environment variables
- Niri socket commands for appearance
- awww wallpaper changes
- dconf settings for GTK apps

Prevents infinite loops with `DARKMAN_RUNNING` environment variable check.

## Common Gotchas

### Ironbar Volume Module
- **Do NOT** use built-in volume module (crashes with PulseAudio)
- Use custom wpctl-based script in `ironbar/modules/volume/`

### Darkman Activation
- Check `DARKMAN_RUNNING` to prevent infinite loops
- Wait for awww-daemon to be ready before sending commands

### USB Autosuspend
- Exclude `usbhid` devices to prevent input lag
- Configured in `modules/hardware/power-management.nix`

### Hardware Configuration
- `hardware-configuration.nix` is auto-generated - don't manually edit
- Host-specific overrides go in `hosts/framework/default.nix`

### State Versions
- System: `25.05`, Home: `25.05`
- **Never change** after initial setup

## Path References
- **Nix store paths:** `${pkgs.tool}/bin/tool`
- **Relative imports:** `./file.nix` (within same directory)
- **Cross-module imports:** `../../path/to/module`
- **Home directory:** Use `~` in scripts, `$HOME`, or `config.home.homeDirectory`

## Module System Usage
- **lib.mkForce** - Override with highest priority
- **lib.mkDefault** - Set with lowest priority
- **lib.mkMerge** - Merge multiple attribute sets
- **lib.mkIf** - Conditional configuration
- **lib.mkBefore/mkAfter** - Order list items

## Documentation
Detailed guides in `docs/`:
- `structure.md` - Repository organization
- `adding-packages.md` - Package management
- `new-host.md` - Adding machines
- `secure-boot.md` - Secure boot setup
- `fingerprint-setup.md` - Fingerprint authentication
- `stylix-darkman-setup.md` - Theming deep dive
- `ironbar-niri-overview.md` - Status bar integration