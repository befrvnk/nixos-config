# Zen Browser Theme Switching

This configuration provides automatic theme switching for Zen Browser that responds to system-wide theme changes via darkman.

## How It Works

1. **userChrome.nix** and **userContent.nix** generate CSS files with both light and dark themes using CSS media queries
2. **CSS Media Queries** automatically select the correct theme based on `prefers-color-scheme`
3. **Darkman** sets the system-wide color preference via freedesktop portal (`org.gnome.desktop.interface.color-scheme`)
4. **Zen Browser** automatically detects the system preference change and applies the correct theme

## Architecture

### CSS Generation

- **userChrome.css**: Styles browser UI elements (toolbars, tabs, menus, etc.)
- **userContent.css**: Styles internal browser pages (about:newtab, about:preferences, etc.)

Both files include light and dark themes:

```css
@media (prefers-color-scheme: dark) {
  /* Dark theme CSS variables and rules */
}

@media (prefers-color-scheme: light) {
  /* Light theme CSS variables and rules */
}
```

### Theme Switching Flow

1. User triggers theme change (manually via `darkman set <mode>` or automatically based on time/location)
2. Darkman activates the appropriate home-manager specialization
3. Darkman sets freedesktop color-scheme: `dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"` or `"'prefer-light'"`
4. Zen Browser detects the system preference change
5. CSS media queries automatically apply the matching theme
6. Theme updates instantly - no browser restart or reload required

## Theme Sources

- **Dark theme**: Catppuccin Mocha (base16 scheme)
- **Light theme**: Catppuccin Latte (base16 scheme)
- **Shared configuration**: `home-manager/themes.nix`

Both themes are based on Stylix's Zen Browser implementation, ensuring compatibility and comprehensive styling.

## Testing

Test theme switching:

```bash
# Switch to dark mode
darkman set dark

# Switch to light mode
darkman set light
```

The browser UI and internal pages should update immediately without restart.

## File Structure

```
home-manager/zen-browser/
├── default.nix          # Main configuration, links CSS files to browser profile
├── userChrome.nix       # Generates browser UI theme CSS
├── userContent.nix      # Generates internal pages theme CSS
└── README.md            # This file
```

## Technical Details

- **CSS location**: `~/.zen/default/chrome/`
- **Theme switching**: Automatic via CSS `@media (prefers-color-scheme)` queries
- **Color scheme**: Base16 palette from YAML files
- **Browser preference**: Reads system `prefers-color-scheme` automatically

## No Manual Configuration Required

Unlike traditional Firefox theming approaches, this setup requires:
- ❌ No `devtools.debugger.remote-enabled` preference
- ❌ No manual reload scripts
- ❌ No browser restarts
- ❌ No direct preference file modification

Everything works automatically through standard web platform features (CSS media queries) and system integration (freedesktop color-scheme portal).

## Troubleshooting

### Theme doesn't update

1. Verify darkman is running:
   ```bash
   systemctl --user status darkman.service
   ```

2. Check that CSS files exist:
   ```bash
   ls -la ~/.zen/*/chrome/userChrome.css
   ls -la ~/.zen/*/chrome/userContent.css
   ```

3. Verify freedesktop color-scheme is set:
   ```bash
   dconf read /org/gnome/desktop/interface/color-scheme
   # Should return 'prefer-dark' or 'prefer-light'
   ```

4. Check darkman logs:
   ```bash
   journalctl --user -u darkman.service -f
   ```

### Browser doesn't respect system theme preference

If Zen Browser doesn't respond to the system color-scheme preference, check:
- Browser version (older versions may not support `prefers-color-scheme` properly)
- Any conflicting browser extensions that override CSS

## Sources

- [Stylix Zen Browser Module](https://github.com/nix-community/stylix/tree/master/modules/zen-browser)
- [CSS prefers-color-scheme](https://developer.mozilla.org/en-US/docs/Web/CSS/@media/prefers-color-scheme)
- [Freedesktop Color Scheme Portal](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html)
