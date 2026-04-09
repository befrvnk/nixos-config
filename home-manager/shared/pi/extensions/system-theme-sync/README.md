# system-theme-sync

Auto-switches pi between its `dark` and `light` themes based on the host system appearance.

Detection strategy:
- macOS: `osascript` checks the system dark mode preference
- Linux: `dconf read /org/gnome/desktop/interface/color-scheme`
- Linux fallback: `darkman get`

On Linux, dconf values containing `default` are treated as light mode so theme sync still works when Stylix temporarily resets the portal preference.

This matches the two hosts in this repository:
- `macbook-darwin`
- `framework`
