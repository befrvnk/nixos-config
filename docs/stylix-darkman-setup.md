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

## Recent Changes (2025-11-10)

### Stylix System-Wide Theming Enabled

We recently migrated to using Stylix's auto-theming capabilities across the entire system:

**Key Changes:**
- **Enabled `stylix.autoEnable = true`**: All supported applications now automatically themed
- **Font update**: Switched to JetBrains Mono for monospace font
- **Simplified configuration**: Removed `themes.nix`, inlined theme definitions into `stylix.nix`
- **Fixed Ghostty theme switching**: Implemented hardcoded dual-theme approach with portal integration
- **Fixed darkman script ordering**: dconf write now happens AFTER specialization activation
- **Removed manual theming**: Cleaned up dunst.nix to prevent conflicts with Stylix

**Files Modified:**
- `home-manager/stylix.nix` - Central theming config, now includes inline theme paths
- `home-manager/ghostty.nix` - New file with hardcoded Catppuccin colors for dual themes
- `home-manager/dunst.nix` - Removed manual font/color settings
- `home-manager/darkman.nix` - Fixed script execution order (specialization → dconf)
- `hosts/framework/home.nix` - Fixed import method for specializations
- `home-manager/themes.nix` - **DELETED** (no longer needed)

**Important Lessons Learned:**
1. Stylix activation can overwrite dconf values - set portal preference AFTER specialization
2. Ghostty reads portal color-scheme on startup, not dynamically - may need restart after theme change
3. Using explicit `import` in home-manager config prevents specializations from building
4. When enabling `autoEnable`, backup existing config files (e.g., GTK CSS) to avoid conflicts

See "Pitfalls & Solutions" below for detailed explanations of issues encountered.

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
- **Automatically restarts after `nixos-rebuild switch`** to re-evaluate current theme

**Why restart on rebuild?**
When rebuilding, the base home-manager configuration (dark theme) is activated. Restarting darkman makes it check the current time and switch to the appropriate theme (light during day, dark at night).

### Niri Integration

When switching themes, scripts also trigger Niri's screen transition effect:
- Finds Niri socket dynamically
- Calls `niri msg action do-screen-transition` for smooth visual fade
- Gracefully skips if Niri isn't running

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
3. Set desktop environment color scheme preference AFTER specialization (for Ghostty and other apps)
4. Trigger Niri screen transition effect for smooth visual feedback

```bash
#!/run/current-system/sw/bin/bash
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DARKMAN_RUNNING=1  # Prevent infinite restart loop

HM_GEN=$(/run/current-system/sw/bin/nix-store -qR /run/current-system | \
  /run/current-system/sw/bin/grep home-manager-generation | \
  while read gen; do
    if [ -d "$gen/specialisation" ]; then
      echo "$gen"
      break
    fi
  done)

# Activate specialization FIRST
"$HM_GEN/specialisation/light/activate"

# Set color scheme preference AFTER (critical order!)
# This ensures Stylix doesn't overwrite it during activation
/run/current-system/sw/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"

# Trigger Niri screen transition effect
NIRI_SOCKET=$(/run/current-system/sw/bin/find /run/user/* -maxdepth 1 -name 'niri*.sock' 2>/dev/null | /run/current-system/sw/bin/head -n1)
if [ -n "$NIRI_SOCKET" ]; then
  NIRI_SOCKET="$NIRI_SOCKET" /nix/store/.../bin/niri msg action do-screen-transition
fi
```

**Desktop Environment Integration:**
The `dconf write` command sets `org.gnome.desktop.interface.color-scheme` in dconf. The `xdg-desktop-portal-gtk` backend reads this setting and exposes it via the freedesktop portal as `org.freedesktop.appearance.color-scheme`. Applications like Ghostty read from the portal to detect the system color scheme preference.

**Critical Ordering:**
The dconf write MUST happen AFTER specialization activation. During specialization activation, Stylix may set the color-scheme to 'default', overwriting any previously set value. By setting it after, we ensure the correct preference is exposed via the portal.

**Requirements:**
- `xdg-desktop-portal-gtk` must be configured as a portal backend (not `xdg-desktop-portal-gnome`)
- The portal reads from dconf's `org.gnome.desktop.interface.color-scheme`
- This works on any desktop environment, not just GNOME
- Some applications (like Ghostty) may only read portal on startup, requiring a restart to see theme changes

#### 3. Darkman Auto-Restart on Rebuild

Home-manager activation script that restarts darkman after each rebuild:

```nix
home.activation.restartDarkman = config.lib.dag.entryAfter ["writeBoundary"] ''
  $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart darkman.service || true
'';
```

**Why this is needed:**
- After `nixos-rebuild switch`, the base home-manager configuration (dark theme) is activated
- Without restart, darkman wouldn't re-evaluate the time until next scheduled check
- Restarting forces immediate re-evaluation, switching to light theme if currently daytime

**Technical details:**
- `entryAfter ["writeBoundary"]` ensures it runs after config files are written
- `$DRY_RUN_CMD` respects home-manager's dry-run mode
- `|| true` prevents activation failure if darkman isn't running

#### 4. Centralized Theme Configuration

**Theme Definitions** (`home-manager/stylix.nix`):

All theme choices are centralized in the stylix configuration with specializations:

```nix
stylix = {
  enable = true;
  autoEnable = true;  # Automatically theme all supported applications
  polarity = "dark";
  base16Scheme = "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
  image = ./wallpapers/mountain.jpg;
  # ... fonts, cursor, etc
};

specialisation = {
  dark.configuration = {
    stylix = {
      polarity = pkgs.lib.mkForce "dark";
      base16Scheme = pkgs.lib.mkForce "${pkgs.base16-schemes}/share/themes/catppuccin-mocha.yaml";
      image = pkgs.lib.mkForce ./wallpapers/mountain.jpg;
    };
  };
  light.configuration = {
    stylix = {
      polarity = pkgs.lib.mkForce "light";
      base16Scheme = pkgs.lib.mkForce "${pkgs.base16-schemes}/share/themes/catppuccin-latte.yaml";
      image = pkgs.lib.mkForce ./wallpapers/mountain.jpg;
    };
  };
};
```

**To change themes:**
1. Update the `base16Scheme` paths in the specializations
2. Rebuild - all applications use the new themes automatically

**Benefits:**
- Single source of truth: Stylix reads base16 scheme files and applies colors everywhere
- No manual color duplication
- All supported applications themed automatically

#### 5. Application-Specific Configuration

**Stylix autoEnable:**

With `stylix.autoEnable = true`, Stylix automatically themes:
- GTK applications
- Ghostty (terminal)
- Swaylock (screen locker)
- Dunst (notifications)
- Ironbar (status bar)
- And many more: https://stylix.danth.me/targets.html

**Niri (compositor):**

Manually configured to use Stylix colors via `osConfig.lib.stylix.colors`:

```nix
focus-ring.active.color = "#${colors.base0D}";
border.active.color = "#${colors.base03}";
```

**Important:** Requires `xdg-desktop-portal-gtk` for proper color scheme detection (see pitfall #11 below).

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

### 8. Ghostty Theme Switching Not Working

**Problem:** Ghostty doesn't switch themes when darkman changes modes.

**Root Cause:** Stylix generates a single theme file that gets overwritten by each specialisation, but Ghostty doesn't detect the file change. Switching between specialisations updates config symlinks but doesn't trigger Ghostty to reload.

**Solution:** Use Ghostty's native light/dark theme support with hardcoded colors:

1. **Extract configuration** to `home-manager/ghostty.nix` for clarity
2. **Hardcode Catppuccin colors** to match Stylix themes:
   ```nix
   let
     # These must exactly match the Stylix theme colors
     darkColors = {
       base00 = "1e1e2e"; base01 = "181825"; # ... Catppuccin Mocha
     };
     lightColors = {
       base00 = "eff1f5"; base01 = "e6e9ef"; # ... Catppuccin Latte
     };
   in
   ```
3. **Generate both theme files**:
   ```nix
   home.file.".config/ghostty/themes/stylix-light".text = mkGhosttyTheme lightColors;
   home.file.".config/ghostty/themes/stylix-dark".text = mkGhosttyTheme darkColors;
   ```
4. **Configure Ghostty** to use both themes:
   ```nix
   programs.ghostty.settings.theme = "light:stylix-light,dark:stylix-dark";
   ```
5. **Disable Stylix auto-theming** for Ghostty:
   ```nix
   stylix.targets.ghostty.enable = false;
   ```
6. **Set desktop environment preference AFTER specialization** in darkman scripts:
   ```bash
   # First activate the specialization
   "$HM_GEN/specialisation/dark/activate"

   # THEN set dconf (after Stylix runs)
   dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
   ```

**Why hardcode colors?**
- Initially tried using `config.lib.stylix.colors` to dynamically generate themes
- Encountered issues with YAML parsing and accessing colors during specialization builds
- Hardcoding ensures both theme files are always present with correct colors
- Trade-off: Must manually update colors if changing from Catppuccin themes

**Why set dconf AFTER specialization?**
- Stylix activation can reset dconf values to 'default'
- Setting dconf after ensures the correct preference is exposed via portal
- Order matters: specialization first, then dconf write

**How it works:**
- Both theme files exist in `~/.config/ghostty/themes/`
- Darkman scripts set dconf `org.gnome.desktop.interface.color-scheme`
- Portal backend (`xdg-desktop-portal-gtk`) exposes this as `org.freedesktop.appearance.color-scheme`
- Ghostty reads from portal and selects the matching theme

**Important:**
- Requires `xdg-desktop-portal-gtk` (see pitfall #11 below)
- **Ghostty may only check portal on startup**, not dynamically
- If theme doesn't switch, restart Ghostty: `killall ghostty && ghostty`

### 9. Theme Reverts to Dark After Rebuild / Infinite Restart Loop

**Problem:** After `nixos-rebuild switch`, theme stays dark even during daytime. Or darkman keeps restarting indefinitely, and Zed doesn't update properly.

**Cause:** The base home-manager configuration defaults to dark theme. Also, if the restart activation runs during specialisation activation (triggered by darkman), it creates an infinite loop: darkman runs specialisation → specialisation restarts darkman → darkman runs specialisation → ...

**Solution:** Use environment variable to signal when running from darkman:

1. Set `DARKMAN_RUNNING=1` at start of darkman scripts:
```bash
#!/run/current-system/sw/bin/bash
export DARKMAN_RUNNING=1
# ... rest of script
"$HM_GEN/specialisation/light/activate"
```

2. Check environment variable in activation script:
```nix
home.activation.restartDarkman = config.lib.dag.entryAfter ["writeBoundary"] ''
  # Check if DARKMAN_RUNNING environment variable is set
  # Use parameter expansion with default to avoid "unbound variable" error
  if [ -z "''${DARKMAN_RUNNING:-}" ]; then
    $DRY_RUN_CMD ${pkgs.systemd}/bin/systemctl --user restart darkman.service || true
  fi
'';
```

**Note:** The `''${DARKMAN_RUNNING:-}` syntax provides an empty default value when the variable is unset, preventing bash "unbound variable" errors.

This forces darkman to check the current time after manual rebuilds, but the environment variable prevents the infinite restart loop when darkman runs the scripts.

### 10. Application Theme Conflicts with Stylix

**Problem:** Applications may have conflicting configuration when enabling `stylix.autoEnable = true`.

**Cause:** Manual theming configurations (fonts, colors, etc.) conflict with Stylix's automatic theming.

**Solution:** Remove manual styling and let Stylix handle it:

```nix
# Before (causes conflicts):
services.dunst.settings.global = {
  font = "monospace 10";
  separator_color = "frame";
  frame_width = 2;
};

# After (Stylix managed):
services.dunst.settings.global = {
  # Font, colors, frame styling managed by Stylix
  # Keep only behavioral/layout settings
  separator_height = 2;
  padding = 8;
};
```

When switching to `autoEnable = true`, you may need to backup/remove existing config files that Stylix wants to manage (e.g., `~/.config/gtk-{3.0,4.0}/gtk.css`).

### 11. Ghostty Theme Not Switching Based on Color Scheme

**Problem:** Setting dconf `org.gnome.desktop.interface.color-scheme` but Ghostty doesn't respond to the change.

**Cause:** Using `xdg-desktop-portal-gnome` which doesn't properly expose the color-scheme setting via the freedesktop portal API. Ghostty reads from `org.freedesktop.appearance.color-scheme` via the portal, not directly from dconf.

**Diagnosis:** Test the portal:
```bash
busctl --user call org.freedesktop.portal.Desktop \
  /org/freedesktop/portal/desktop \
  org.freedesktop.portal.Settings Read ss \
  org.freedesktop.appearance color-scheme
```

Should return:
- `v v u 1` for dark mode (`prefer-dark`)
- `v v u 2` for light mode (`prefer-light`)
- `v v u 0` means no preference or portal isn't reading dconf correctly

**Solution:** Use `xdg-desktop-portal-gtk` instead:
```nix
xdg.portal = {
  enable = true;
  extraPortals = [ pkgs.xdg-desktop-portal-gtk ];  # Not xdg-desktop-portal-gnome
  configPackages = [ pkgs.niri ];
};
```

After rebuilding and restarting portals, the test should return the correct value.

**Additional Note:** Even with portal working correctly, Ghostty may only read the color-scheme preference on startup. Running instances might not detect changes. If theme doesn't switch after `darkman set dark/light`, restart Ghostty.

### 12. Home-Manager Profile Not Updated

**Problem:** Running specialisation activate script but `~/.local/state/nix/profiles/home-manager` still points to old generation.

**Cause:** This is expected! The activation script creates a new generation but the symlink update happens separately.

**Solution:** This is actually fine - the configs in `~/.config/` are updated correctly. The profile link will update on next full home-manager activation.

### 13. Stylix Overwrites dconf Color Scheme Setting

**Problem:** Setting `dconf write /org/gnome/desktop/interface/color-scheme` in darkman scripts, but it gets overwritten or doesn't persist correctly.

**Cause:** When the darkman script runs the specialization activation, Stylix may set the dconf value to 'default' as part of its theming setup, overwriting the value set earlier in the script.

**Solution:** Set the dconf value AFTER specialization activation:
```bash
#!/run/current-system/sw/bin/bash
export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
export DARKMAN_RUNNING=1

# Find and activate specialization FIRST
HM_GEN=$(...)
"$HM_GEN/specialisation/dark/activate"

# Set dconf AFTER specialization (this is critical!)
dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"

# Then trigger visual effects
NIRI_SOCKET=$(...)
```

**Why this works:**
- Specialization activation runs Stylix which may modify dconf
- Setting dconf after ensures your preference takes precedence
- Portal then correctly exposes the preference to applications

### 14. Home-Manager Import Method Prevents Specializations

**Problem:** Home-manager specializations directory not being created in the system closure, even though they're defined in configuration.

**Cause:** Using explicit `import` function in the host configuration prevents proper module evaluation:
```nix
# This breaks specializations:
users.frank = import ../../home-manager/frank.nix;
```

**Solution:** Use path-only reference without `import`:
```nix
# This works correctly:
users.frank = ../../home-manager/frank.nix;
```

Home-manager needs to evaluate the module itself to properly handle specializations. The explicit `import` evaluates the file too early in the process.

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
   Some apps support live reload without restart (Firefox, kitty, Ironbar). Could add specific reload commands to scripts. ✅ Already implemented for Niri via screen transition effect.

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
- `home-manager/stylix.nix` - **Centralized theme definitions with specializations** (change themes here!)
- `home-manager/ghostty.nix` - Ghostty configuration (automatically themed by Stylix)
- `flake.nix` - Stylix module imports
