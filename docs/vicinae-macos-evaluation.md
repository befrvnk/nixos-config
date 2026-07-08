# Vicinae macOS Evaluation

This note records the July 2026 attempt to replace Raycast with Vicinae on macOS and the current decision to keep Raycast until Vicinae's macOS window-management backend works reliably in this setup.

## Goal

Evaluate whether Vicinae can replace Raycast for the current macOS workflow:

- application launching
- inline calculator
- window placement/sizing
- AI writing/text rewrite commands

## Current decision

Keep **Raycast** as the primary macOS launcher/window manager for now.

Vicinae is promising and works for some launcher features, but the macOS window-management backend currently returns no windows on this machine, even after granting Accessibility permission. Because window placement/sizing is a required Raycast feature, Vicinae is not ready to replace Raycast here yet.

## What worked

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

## Configuration state

Vicinae remains installed on Darwin for manual testing, but the following were disabled so Raycast can remain primary:

- Vicinae launchd autostart
- `skhd` `Cmd+Space` binding
- temporary Vicinae window-management debug hotkeys

Raycast remains installed via Homebrew cask in `hosts/macbook-darwin/default.nix`.

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

## Future follow-up

Revisit when Vicinae has a newer stable macOS release. Suggested checklist:

1. Update the Vicinae flake input to the new stable release.
2. Test the built-in **Switch Windows** command first.
3. Run the custom debug command and confirm `windows` is non-empty.
4. Only then re-enable launcher/window-manager hotkeys.
5. Replace the internal `globalThis.vicinae.client.WindowManagement.setWindowBounds` shim once Vicinae exposes a public TypeScript API for setting window bounds.

If using the official DMG as a control, test whether it can enumerate windows with the same Accessibility permission. That result determines whether to report a Nix packaging/TCC issue or a general Vicinae macOS backend issue upstream.
