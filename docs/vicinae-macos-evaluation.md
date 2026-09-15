# Vicinae macOS Evaluation

This note records the July 2026 attempt to replace Raycast with Vicinae on macOS and the September 2026 retry with the official macOS release.

## Goal

Evaluate whether Vicinae can replace Raycast for the current macOS workflow:

- application launching
- inline calculator
- window placement/sizing
- AI writing/text rewrite commands

## Current decision

Use **Vicinae v0.28.1** as the primary macOS launcher/window manager without retaining Raycast as an installed fallback.

The retry uses the official signed Homebrew cask instead of the Nix-built app. This gives macOS a stable app identity for Accessibility permission, which is required for window management, selected-text access, and pasting rewritten text.

The configured essentials are:

- Agenda for iCal schedules and Google Meet links
- the local Gemini Text Tools extension for Improve Text
- the local Brightness extension for BetterDisplay-backed display brightness
- the local window layout extension, alongside Vicinae's built-in window switcher

## July 2026 results

- Vicinae v0.23.0 builds through the upstream flake on Darwin.
- `vicinae server` plus `vicinae toggle` opens the launcher.
- `skhd` can bind `Cmd+Space` to `vicinae toggle`.
- The custom Vicinae extension can load and reach Vicinae's internal extension runtime.
- The internal `WindowManagement.setWindowBounds` RPC is available at runtime.

## What did not work

Vicinae's macOS window backend could not enumerate windows:

```json
{
  "internalSetWindowBoundsAvailable": true,
  "activeWindow": { "error": "No active window" },
  "windows": [],
  "activeWindowCandidates": []
}
```

This means the custom extension was able to reach the hidden/internal bounds API, but Vicinae itself could not provide a target window.

The issue reproduced when launching Vicinae both ways:

1. via the nix-darwin launchd agent running `vicinae server`
2. directly as the `.app` bundle with `open -n "$app" --args ...`

So this was not just a launchd-vs-LaunchServices problem.

## Accessibility/TCC observations

The Nix-built Vicinae app is ad-hoc signed and lives in a changing Nix store path, for example:

```text
/nix/store/...-vicinae-0.23.0/Applications/Vicinae.app
```

`codesign -dv` showed:

```text
Identifier=Vicinae
Signature=adhoc
TeamIdentifier=not set
Info.plist=not bound
Sealed Resources=none
```

macOS Accessibility/TCC can be sensitive to app identity, signing, and path. The app was re-added to **System Settings > Privacy & Security > Accessibility**, but Vicinae still returned an empty window list.

If revisiting this, compare against the official notarized Vicinae DMG release. If the DMG sees windows but the Nix build does not, the problem is likely Nix/ad-hoc signing/TCC identity. If the DMG also sees no windows, report it as an upstream Vicinae macOS backend bug.

## Custom extension status

A local extension was added under:

```text
home-manager/darwin/vicinae/extensions/window-management/
```

It includes commands such as:

- `left-half`
- `right-half`
- `two-thirds-left`
- `two-thirds-right`
- `debug-active-window`

The extension is currently useful for debugging but cannot move windows until Vicinae can return an active window or list windows.

The extension originally used a deep import:

```ts
@vicinae/api/dist/api/client
```

That built but failed at runtime because Vicinae's extension runtime only shims the top-level `@vicinae/api` package. The shim was changed to use `globalThis.vicinae.client` instead.

## Important deeplink detail

Installed local extensions are namespaced by author. For this extension, valid deeplinks use:

```text
@frank/window-management
```

Correct examples:

```sh
vicinae 'vicinae://launch/@frank/window-management/debug-active-window'
vicinae 'vicinae://launch/@frank/window-management/two-thirds-left'
```

Incorrect examples:

```sh
vicinae 'vicinae://launch/window-management/debug-active-window'
```

The incorrect form fails with:

```text
window-management:debug-active-window does not refer to a valid entrypoint
```

## Previous configuration state

The Nix-built Vicinae remained installed on Darwin for manual testing, but the following were disabled so Raycast could remain primary:

- Vicinae launchd autostart
- `skhd` `Cmd+Space` binding
- temporary Vicinae window-management debug hotkeys

Raycast was installed via Homebrew cask in `hosts/macbook-darwin/default.nix` during this evaluation.

Manual testing commands:

```sh
vicinae server
vicinae toggle
vicinae 'vicinae://launch/@frank/window-management/debug-active-window'
```

Cleanup if Vicinae is running and Raycast should be primary:

```sh
launchctl bootout gui/501 ~/Library/LaunchAgents/vicinae.server.plist 2>/dev/null || true
launchctl bootout gui/501 ~/Library/LaunchAgents/org.nixos.skhd.plist 2>/dev/null || true
pkill -f 'Vicinae'
pkill -f 'vicinae-ext-runtime'
```

## September 2026 retry

Vicinae v0.28.1 is installed from the official Homebrew cask. On first launch:

1. Complete onboarding and grant Accessibility permission.
2. Keep the default `Option+Space` launcher shortcut, or change it to `Cmd+Space` in General Settings.
3. Open **Manage Calendars**, add each private Google Calendar iCal URL, then use **Upcoming Events**. Google Meet links appear as an **Open Google Meet** action.
4. Open the Gemini Text Tools preferences and add the Google AI Studio API key. To use **Improve Text**, select text, copy it with `Cmd+C`, then run the command. Review the highlighted changes and choose **Paste Result** or **Copy Result**.
5. Test the built-in **Switch Windows** command, then the custom window layout commands.
6. Test the Brightness commands (Increase, Decrease, Set, Maximize, Show). They require BetterDisplay to be installed and running, and call `betterdisplaycli` from the Homebrew cask. The target display and step size are configured in the extension preferences.

The custom layout extension invokes Rectangle's documented URL actions for the final resize. Vicinae v0.28.1 returns the focused window correctly, but its internal bounds RPC rejects that window when it is absent from a separate server-side cache. Grant Accessibility permission to Rectangle when prompted; `osascript` does not need assistive access. If Vicinae window enumeration fails entirely, run **Debug Active Window** and report the result upstream.

## BetterDisplay brightness

The Brightness extension (`home-manager/darwin/vicinae/extensions/brightness/`) replaces the Lunar-based Raycast Brightness Control workflow. It shells out to `betterdisplaycli` (default `/opt/homebrew/bin/betterdisplaycli`) using the `get`/`set -brightness` operations for the selected display target (`displayWithMouse`, `displayWithMainStatus`, or `displayWithFocus`). Lunar is no longer installed.
