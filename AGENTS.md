# NixOS Configuration Agent Guidelines

## Build & Test Commands

**Important:** This configuration uses [nh](https://github.com/nix-community/nh) (Nix Helper) instead of `nixos-rebuild`. Always prefer `nh` commands for better output, faster builds, and visual diffs.

**Note for AI Agents:** Do NOT run any commands requiring `sudo`. If a task requires sudo privileges, inform the user and ask them to run the command manually. The commands below are documented for reference only.

### Primary Commands (use these)
- **Rebuild system:** `nh os switch ~/nixos-config` or `nh os switch` (auto-detects config)
- **Test without activating:** `nh os test ~/nixos-config` (builds but doesn't set as boot default)
- **Update and rebuild:** `nh os switch ~/nixos-config --update` (updates flake.lock and rebuilds)
- **Clean old generations:** `nh clean all --keep 5` (keeps last 5 generations)
- **Search packages:** `nh search <package-name>`

### Additional Commands
- **Check flake validity:** `nix flake check`
- **Format code:** `nix fmt` (auto-formatted on commit via pre-commit hooks)
- **Update flakes manually:** `nix flake update`
- **Dry-run build:** `nix build .#nixosConfigurations.framework.config.system.build.toplevel --dry-run`

### Legacy Commands (avoid these)
- ❌ `nixos-rebuild switch` → Use `nh os switch` instead
- ❌ `nixos-rebuild test` → Use `nh os test` instead
- ❌ `nix-collect-garbage` → Use `nh clean all` instead

### Commands Requiring User Intervention (DO NOT RUN)

**AI Agents must NOT execute these commands.** Document them in responses and ask the user to run them manually:

- **Rollback to previous generation:** `sudo nixos-rebuild switch --rollback`
- **List all generations:** `sudo nix-env --list-generations --profile /nix/var/nix/profiles/system`
- **Boot into specific generation:** `sudo nixos-rebuild switch --rollback --generation <number>`
- **Hardware scans:** `sudo nixos-generate-config --show-hardware-config`
- **Systemd system services:** `sudo systemctl <start|stop|restart|status> <service>`
- **Any command with sudo:** Inform the user and provide the command for them to run

### Safe Commands for Agents

Agents CAN safely run these commands without sudo:

- **All nh commands:** `nh os switch`, `nh os test`, `nh clean all`, etc.
- **Nix commands:** `nix flake check`, `nix flake update`, `nix fmt`, `nix build`
- **Git operations:** `git add`, `git commit`, `git push`, `git status`, etc.
- **User systemd services:** `systemctl --user status/start/stop/restart <service>`
- **File operations:** Read, Edit, Write tools for configuration files
- **Directory operations:** `ls`, `tree`, `fd`, file searches

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
- Use `nh os switch` or the `rebuild` alias from zsh for convenient system rebuilding
- Test changes with `nh os test` before committing to ensure they work
- Use `nh os switch --update` to update flakes and rebuild in one command
- Clean old generations periodically with `nh clean all --keep 5`

## Why nh (Nix Helper)?

This project uses [nh](https://github.com/nix-community/nh) as a wrapper around NixOS/home-manager commands. Benefits:

- **Better output:** Colored, structured progress output with build summaries
- **Faster builds:** Automatic specialization detection and optimized rebuild paths
- **Visual diffs:** Shows package changes before/after rebuild
- **Simpler commands:** Auto-detects hostname and config location
- **Safer garbage collection:** `nh clean` provides better control over generation cleanup
- **Unified interface:** Single tool for OS, home-manager, and package management

**When to use what:**
- System rebuilds: `nh os switch` (not `nixos-rebuild`)
- Home-manager: `nh home switch` (if using standalone home-manager)
- Package search: `nh search` (alternative to `nix search`)
- Cleanup: `nh clean all --keep N` (not `nix-collect-garbage`)
- Flake operations: Still use `nix flake update`, `nix flake check`, `nix fmt`

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
- **System package:** Add to `modules/system/packages.nix`, then run `nh os switch`
- **User package:** Add to `home-manager/packages.nix`, then run `nh os switch`
- **Custom package:** Create overlay in `overlays/`, then run `nh os switch`
- **Test first:** Use `nh os test` to verify the package builds before switching

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

**After creating the service:**
1. Test the configuration: `nh os test` (or `nh home test` for home-manager services)
2. Apply the changes: `nh os switch`
3. Check service status: `systemctl --user status my-service` (user services don't need sudo)

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