# Hamr Launcher Setup

Hamr is an extensible launcher for Wayland compositors built with Quickshell. It provides application launching, plugins, and integrates with the system theme.

## Package Structure

```
pkgs/hamr/
├── package.nix     # Package derivation with NixOS patches
└── hm-module.nix   # Home-manager module (programs.hamr.enable)

home-manager/
└── hamr.nix        # User configuration with Stylix colors
```

## Installation

The package is available via overlay and enabled through home-manager:

```nix
# home-manager/hamr.nix
{ ... }:
{
  programs.hamr.enable = true;
}
```

## NixOS-Specific Patches

The package includes patches for NixOS compatibility:

### 1. XDG_DATA_DIRS for Application Discovery

Hamr's apps plugin uses hardcoded paths that don't include NixOS locations. The package patches `handler.py` to use `XDG_DATA_DIRS`:

```python
APP_DIRS = [Path(d) / "applications" for d in os.environ.get("XDG_DATA_DIRS", "").split(":") if d] + [...]
```

This allows hamr to find applications from:
- System packages (`/run/current-system/sw/share/applications/`)
- Home-manager packages (via XDG_DATA_DIRS)
- Standard locations as fallback

### 2. Qt5Compat for GraphicalEffects

Hamr requires Qt5Compat.GraphicalEffects which isn't included in nixpkgs' quickshell. The package wraps quickshell with the required QML import path:

```nix
quickshellWrapped = quickshell.overrideAttrs (old: {
  postFixup = (old.postFixup or "") + ''
    wrapProgram $out/bin/quickshell \
      --prefix QML2_IMPORT_PATH : "${qt6Packages.qt5compat}/lib/qt-6/qml"
  '';
});
```

## Stylix Theme Integration

Hamr uses Material Design 3 colors loaded from `~/.config/hamr/colors.json`. The configuration generates this file from Stylix's base16 colors:

```nix
# Mapping base16 to Material Design 3
{
  "background": base00,      # Background color
  "on_background": base05,   # Text on background
  "primary": base0D,         # Primary accent (blue)
  "secondary": base0C,       # Secondary accent (teal)
  "tertiary": base0E,        # Tertiary accent (mauve)
  "error": base08,           # Error color (red)
  "outline": base05,         # Secondary text (uses main text for readability)
  ...
}
```

### Theme Switching

Theme switching is handled by darkman, which:
1. Activates the appropriate Stylix specialization (dark/light)
2. Restarts hamr to pick up the regenerated colors.json

The restart is added to `darkman-switch-mode.sh`:
```bash
@systemd@/bin/systemctl --user restart hamr.service || true
```

## Systemd Service

The home-manager module creates a systemd user service that auto-starts with the graphical session:

```nix
systemd.user.services.hamr = {
  Unit = {
    Description = "Hamr launcher daemon";
    PartOf = [ "graphical-session.target" ];
    After = [ "graphical-session.target" ];
  };
  Service = {
    Type = "simple";
    ExecStart = "${cfg.package}/bin/hamr";
    Restart = "on-failure";
    RestartSec = 5;
  };
  Install.WantedBy = [ "graphical-session.target" ];
};
```

## Keybindings

Configured in `home-manager/niri/binds.nix`:

| Key | Action |
|-----|--------|
| `Mod+Shift+Space` | Toggle hamr launcher |

## Usage

```bash
# Toggle launcher (or use keybinding)
hamr toggle

# Open specific plugin
hamr plugin clipboard
hamr plugin emoji

# Audio controls
hamr audio play notification
hamr audio enable/disable
```

## Dependencies

Runtime dependencies included in the package:
- quickshell (with Qt5Compat)
- Python 3 with click, loguru, tqdm, pygobject3
- fd, fzf (file/fuzzy search)
- wl-clipboard, cliphist (clipboard)
- libqalculate (calculator)
- grim, slurp (screenshots)
- tesseract (OCR)
- playerctl (media control)

Font dependencies (installed separately):
- material-symbols (icons)
- JetBrainsMono Nerd Font (via Stylix)

## Troubleshooting

### Apps not showing

Check that `XDG_DATA_DIRS` includes your application directories:
```bash
echo $XDG_DATA_DIRS | tr ':' '\n'
```

### Theme colors not updating

Restart hamr after theme switch:
```bash
systemctl --user restart hamr.service
```

### Qt5Compat errors

If you see "module Qt5Compat.GraphicalEffects is not installed", ensure the package is using the wrapped quickshell with QML2_IMPORT_PATH set.
