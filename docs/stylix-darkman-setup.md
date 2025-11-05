# Stylix & Darkman Theme Switching Setup

This document explains our stylix configuration with automatic light/dark theme switching using darkman.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Configuration Details](#configuration-details)
- [How It Works](#how-it-works)
- [Pitfalls & Solutions](#pitfalls--solutions)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)

## Overview

### What is Stylix?

Stylix is a NixOS/Home Manager module that provides system-wide theming. It automatically generates and applies color schemes to a wide range of applications using:
- Base16 color schemes
- Wallpapers (can extract colors from images)
- Font configurations
- Cursor themes

### What is Darkman?

Darkman is a framework for automatic dark-mode and light-mode transitions on Unix-like desktops. It:
- Switches themes based on sunrise/sunset times for your location
- Runs scripts when switching between light and dark modes
- Provides manual theme switching via `darkman set light/dark`

### Our Setup

We combine:
1. **Stylix** for unified theming across all applications
2. **Home-manager specialisations** for light/dark theme variants
3. **Darkman** for automatic time-based theme switching
4. **Catppuccin themes**: Latte (light) and Mocha (dark)

## Architecture

### System Level (`modules/stylix.nix`)

```nix
stylix = {
  enable = true;
  autoEnable = true;  # Automatically theme all supported applications
  base16Scheme = "catppuccin-mocha.yaml";
  image = <wallpaper>;

  homeManagerIntegration = {
    autoImport = false;      # We manually import in flake.nix
    followSystem = false;    # Home-manager has its own theme config
  };
};
```

### Home-Manager Level (`home-manager/frank.nix`)

**Base Configuration:**
- Sets default theme (dark/catppuccin-mocha)
- Configures fonts, cursor, common settings
- `autoEnable = true` to theme all applications

**Specialisations:**
```nix
specialisation = {
  dark.configuration = {
    stylix = {
      polarity = lib.mkForce "dark";
      base16Scheme = lib.mkForce "catppuccin-mocha.yaml";
      image = lib.mkForce ./wallpapers/catppuccin-mocha.jpg;
    };
  };
  light.configuration = {
    stylix = {
      polarity = lib.mkForce "light";
      base16Scheme = lib.mkForce "catppuccin-latte.yaml";
      image = lib.mkForce ./wallpapers/catppuccin-mocha.jpg;
    };
  };
};
```

### Darkman Integration (`modules/darkman.nix`)

Systemd user service that:
- Runs on login
- Monitors sunrise/sunset times for Munich (48.13743°N, 11.57549°E)
- Executes scripts in `~/.local/share/light-mode.d/` and `~/.local/share/dark-mode.d/`

## Configuration Details

### File Locations

```
nixos-config/
├── modules/
│   ├── darkman.nix          # Darkman systemd service
│   └── stylix.nix            # System-level stylix config
├── home-manager/
│   ├── frank.nix             # Home-manager config with specialisations
│   └── wallpapers/
│       └── catppuccin-mocha.jpg
└── flake.nix                 # Imports stylix.homeModules.stylix
```

### Key Configuration Sections

#### 1. Flake.nix - Stylix Module Import

```nix
home-manager = {
  sharedModules = [
    stylix.homeModules.stylix  # Import home-manager stylix module
    # ... other modules
  ];
};
```

#### 2. Darkman Scripts

Scripts are placed in `~/.local/share/light-mode.d/` and `~/.local/share/dark-mode.d/` (NOT in a `darkman/` subdirectory!).

**Critical Requirements:**
- Use absolute path to bash: `#!/run/current-system/sw/bin/bash`
- Use absolute paths for all commands: `/run/current-system/sw/bin/nix-store`
- Scripts must be executable

**Script Logic:**
1. Find home-manager generation with specialisations from current system
2. Execute the appropriate specialisation's activation script

```bash
#!/run/current-system/sw/bin/bash
HM_GEN=$(/run/current-system/sw/bin/nix-store -qR /run/current-system | \
  /run/current-system/sw/bin/grep home-manager-generation | \
  while read gen; do
    if [ -d "$gen/specialisation" ]; then
      echo "$gen"
      break
    fi
  done)

"$HM_GEN/specialisation/light/activate"
```

#### 3. Application-Specific Configuration

**Ghostty:**
Must be enabled via `programs.ghostty.enable = true` (not just as a package):

```nix
programs.ghostty = {
  enable = true;
  package = pkgs-unstable.ghostty;
};
```

**Zed:**
Automatically themed when `stylix.autoEnable = true`

**Other Applications:**
Stylix supports many applications out of the box. See: https://stylix.danth.me/targets.html

## How It Works

### 1. Build Time

When you run `sudo nixos-rebuild switch --flake .#framework`:

1. **System builds three home-manager generations:**
   - Base generation (dark theme)
   - Dark specialisation → symlinks to base generation
   - Light specialisation → separate generation with light theme

2. **Generations are stored in system closure:**
   ```
   /nix/store/...-home-manager-generation/
   ├── activate
   ├── bin/
   ├── home-files/
   └── specialisation/
       ├── dark -> /nix/store/...-home-manager-generation  (dark)
       └── light -> /nix/store/...-home-manager-generation (light)
   ```

3. **Darkman service starts:**
   - Loads configuration from `~/.config/darkman/config.yaml`
   - Determines current mode based on time/location
   - Runs appropriate mode scripts

### 2. Runtime - Theme Switching

When darkman switches themes (automatic at sunrise/sunset or manual via `darkman set`):

1. **Darkman executes scripts** in `~/.local/share/{light,dark}-mode.d/`

2. **Script finds specialisation:**
   - Queries current system's home-manager generations
   - Finds the one with specialisations

3. **Activates specialisation:**
   - Runs `/nix/store/...-home-manager-generation/specialisation/{light,dark}/activate`
   - This updates symlinks in `~/.config/` to new theme files
   - Creates new home-manager profile generation

4. **Applications reload:**
   - Some apps (Zed, Ghostty) automatically detect config changes
   - Others need restart to pick up new theme

### 3. Home-Manager Integration

**Why NOT use standalone home-manager?**

We use home-manager as a NixOS module, which means:
- Home-manager is built as part of `nixos-rebuild switch`
- No separate `home-manager switch` needed for system changes
- Specialisations are built into system closure

**Key Difference:**
- Standalone: `home-manager switch --specialisation light`
- NixOS module: Direct activation script execution

## Pitfalls & Solutions

### 1. Home-Manager Specialisations Don't Build

**Problem:** Specialisations directory not created in home-manager generation.

**Cause:** Initially had system-level stylix.nix that was being imported and conflicting.

**Solution:**
- Remove old `modules/stylix.nix` that didn't set `homeManagerIntegration`
- Create new one with proper integration settings:
  ```nix
  homeManagerIntegration = {
    autoImport = false;    # We manually import
    followSystem = false;  # Home-manager has own config
  };
  ```

### 2. Package Rename: noto-fonts-emoji

**Problem:** Build error: `'noto-fonts-emoji' has been renamed to 'noto-fonts-color-emoji'`

**Solution:** Update font configuration:
```nix
emoji = {
  package = pkgs.noto-fonts-color-emoji;  # Not noto-fonts-emoji
  name = "Noto Color Emoji";
};
```

### 3. Darkman Scripts in Wrong Directory

**Problem:** Darkman says "Notifying all transition handlers" but scripts don't run.

**Cause:** Scripts were in `~/.local/share/darkman/light-mode.d/` but darkman looks for `~/.local/share/light-mode.d/` (no darkman subdirectory).

**Solution:** Place scripts directly in:
- `~/.local/share/light-mode.d/`
- `~/.local/share/dark-mode.d/`

### 4. Scripts Fail with Exit Status 127

**Problem:**
```
darkman[...]: scripts.go:66: Failed to run: exit status 127.
darkman[...]: env: 'bash': No such file or directory
```

**Cause:** Darkman runs scripts without user PATH. Can't find `bash` or `nix-store`.

**Solution:** Use absolute paths for EVERYTHING:
```bash
#!/run/current-system/sw/bin/bash  # Not #!/usr/bin/env bash
/run/current-system/sw/bin/nix-store  # Not just nix-store
/run/current-system/sw/bin/grep       # Not just grep
```

### 5. `home-manager switch --specialisation` Doesn't Work

**Problem:** Command fails with "No configuration file found at ~/.config/home-manager/home.nix"

**Cause:** When home-manager is used as a NixOS module, it doesn't create standalone config.

**Solution:** Don't use `home-manager` CLI for switching. Instead, directly execute activation scripts:
```bash
/nix/store/...-home-manager-generation/specialisation/light/activate
```

### 6. Specialisations Use Same Generation

**Problem:** Both dark and light specialisations point to same store path.

**Cause:** Forgot to use `lib.mkForce` to override base configuration values.

**Solution:** Use `lib.mkForce` in specialisations:
```nix
specialisation.light.configuration = {
  stylix.polarity = pkgs.lib.mkForce "light";
  stylix.base16Scheme = pkgs.lib.mkForce "catppuccin-latte.yaml";
};
```

### 7. Applications Not Themed

**Problem:** Stylix generates config but applications don't use it.

**Cause:** `stylix.autoEnable = false` means only explicitly enabled targets get themed.

**Solution:** Set `stylix.autoEnable = true` to theme all supported applications automatically.

### 8. Ghostty Not Themed

**Problem:** Ghostty doesn't switch themes even though Zed works.

**Cause:** Ghostty was installed as a package, not via `programs.ghostty` module.

**Solution:** Enable Ghostty via home-manager module:
```nix
programs.ghostty = {
  enable = true;
  package = pkgs-unstable.ghostty;
};
```
Remove from `home.packages`.

### 9. Home-Manager Profile Not Updated

**Problem:** Running specialisation activate script but `~/.local/state/nix/profiles/home-manager` still points to old generation.

**Cause:** This is expected! The activation script creates a new generation but the symlink update happens separately.

**Solution:** This is actually fine - the configs in `~/.config/` are updated correctly. The profile link will update on next full home-manager activation.

## Usage

### Automatic Switching

Darkman automatically switches themes:
- **Sunrise:** Switches to light theme (Catppuccin Latte)
- **Sunset:** Switches to dark theme (Catppuccin Mocha)

Location configured in `~/.config/darkman/config.yaml`:
```yaml
lat: 48.13743  # Munich, Germany
lng: 11.57549
```

### Manual Switching

```bash
# Switch to dark theme
darkman set dark

# Switch to light theme
darkman set light

# Check current theme
darkman get

# Toggle between themes (if you add a toggle script)
darkman toggle
```

### Verify Service Status

```bash
# Check darkman service
systemctl --user status darkman

# View darkman logs
journalctl --user -u darkman -f

# Restart darkman
systemctl --user restart darkman
```

### Test Theme Switching

1. **Open themed applications** (Zed, Ghostty, terminal)
2. **Switch theme:** `darkman set light`
3. **Verify:** Applications should switch to light theme
4. **Switch back:** `darkman set dark`
5. **Verify:** Applications should switch to dark theme

**Note:** Some applications may need to be restarted to pick up theme changes.

## Troubleshooting

### Theme Not Switching

1. **Check darkman logs:**
   ```bash
   journalctl --user -u darkman --no-pager -n 50
   ```

2. **Look for errors:**
   - "Failed to run: exit status 127" → Script has PATH issues
   - "No such file or directory" → Script location wrong
   - No script execution → Scripts not in correct directory

3. **Manually test scripts:**
   ```bash
   bash -x ~/.local/share/light-mode.d/stylix.sh
   ```

4. **Verify script locations:**
   ```bash
   ls -la ~/.local/share/light-mode.d/
   ls -la ~/.local/share/dark-mode.d/
   ```

### Specialisations Not Built

1. **Check system's home-manager generations:**
   ```bash
   nix-store -qR /run/current-system | grep home-manager-generation
   ```

2. **Check for specialisation directory:**
   ```bash
   # For each generation found above:
   ls -la /nix/store/...-home-manager-generation/specialisation/
   ```

3. **If missing:** Rebuild system:
   ```bash
   sudo nixos-rebuild switch --flake .#framework
   ```

### Application Not Themed

1. **Check if stylix supports it:** https://stylix.danth.me/targets.html

2. **Verify autoEnable is true:**
   ```bash
   grep "autoEnable" ~/nixos-config/home-manager/frank.nix
   ```

3. **For programs with home-manager modules:** Enable via `programs.<app>.enable`

4. **Check generated config:**
   ```bash
   ls -la ~/.config/<app>/
   # Should be symlinks to /nix/store/...-home-manager-files/
   ```

### Darkman Not Running

1. **Check service status:**
   ```bash
   systemctl --user status darkman
   ```

2. **Start if stopped:**
   ```bash
   systemctl --user start darkman
   ```

3. **Enable for auto-start:**
   ```bash
   systemctl --user enable darkman
   ```

4. **Check configuration:**
   ```bash
   cat ~/.config/darkman/config.yaml
   ```

## Future Improvements

### Potential Enhancements

1. **Manual Toggle Script:**
   Create a `toggle-theme` command for quick manual switching:
   ```bash
   current=$(darkman get)
   if [ "$current" = "dark" ]; then
     darkman set light
   else
     darkman set dark
   fi
   ```

2. **Application-Specific Reload Hooks:**
   Some apps support live reload without restart (Firefox, kitty, Waybar). Could add specific reload commands to scripts.

3. **Notification on Theme Switch:**
   Add desktop notification when theme switches:
   ```bash
   notify-send "Theme" "Switched to $mode mode"
   ```

4. **GTK Theme Integration:**
   Ensure GTK apps also switch themes properly.

## References

- [Stylix Documentation](https://stylix.danth.me/)
- [Darkman Documentation](https://darkman.whynothugo.nl/)
- [Home-Manager Specialisations](https://nix-community.github.io/home-manager/index.xhtml#sec-usage-specialisation)
- [Catppuccin Theme](https://github.com/catppuccin/catppuccin)
- [Base16 Color Schemes](https://github.com/tinted-theming/base16-schemes)

## Related Files

- `modules/stylix.nix` - System-level stylix configuration
- `modules/darkman.nix` - Darkman systemd service
- `home-manager/frank.nix` - Home-manager config with specialisations
- `flake.nix` - Stylix module imports
