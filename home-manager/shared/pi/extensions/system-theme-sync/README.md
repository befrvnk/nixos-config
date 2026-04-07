# system-theme-sync

Auto-switches pi between its `dark` and `light` themes based on the host system appearance.

Detection strategy:
- macOS: `osascript` checks the system dark mode preference
- Linux: `dconf read /org/gnome/desktop/interface/color-scheme`
- Linux fallback: `darkman get`

This matches the two hosts in this repository:
- `macbook-darwin`
- `framework`
