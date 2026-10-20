# Switch from Asyar back to Vicinae

The September 16 migration (`396df47`) replaced the launcher on both desktop
platforms. The restoration selectively recovers the configuration and custom
extensions from `171c092`, while keeping later unrelated updates and GTK/Qt
appearance configuration. Vicinae is pinned to v0.29.2; the extension collection
is pinned to its pre-Asyar revision, `ee117bc`.

## Before activating (both machines)

Quit Asyar first and disable its login item on macOS. From this repository run:

```sh
bash scripts/backup-launcher-data.sh
```

The private archive is saved under `~/launcher-backups/`. It includes standard
Asyar app data and any existing Vicinae configuration/data, following deployed
Home Manager symlinks so it does not depend on old Nix store paths. If you use a
custom `XDG_CONFIG_HOME`, `XDG_DATA_HOME`, or other nonstandard data location,
back that up separately. Keep the archive out of Git: preferences, calendar
feeds, cached events, and API keys can be sensitive.

**macOS warning:** Homebrew activation uses `cleanup = "zap"`. Removing the
Asyar cask can delete its settings, caches, and WebKit storage. A previous Nix
generation alone cannot recover that data. Do not activate without a backup.
Removing the tracked extension sources does not delete personal app data.

## MacBook

Build without activation:

```sh
nix build .#darwinConfigurations.macbook.system --no-link --accept-flake-config
```

Then run the activation yourself (it may request administrator privileges):

```sh
nh darwin switch .
```

Launch the signed Homebrew Vicinae app. Configure Accessibility, the global
shortcut, and launch-at-login in the app. These settings are not managed by the
Darwin module. Follow [the extension setup](macbook-darwin-setup.md#application-launcher-vicinae).

## Framework

Take the backup on the Framework too; the MacBook backup does not cover it.
Test the new system before making it the persistent default:

```sh
nh os test .
```

Verify `Mod+Space` opens Vicinae, `systemctl --user status vicinae` is healthy,
Asyar is no longer running, and both `darkman set dark` and `darkman set light`
update the launcher theme. Test the Nix, Wi-Fi, and Gemini extensions. Bluetooth
is still disabled because of its earlier Node.js/usocket build problem.

Once satisfied:

```sh
rebuild switch
```

## Feature differences and smoke tests

- Test application search and calculator on both machines, then restart/login
  to check autostart and ensure there is only one launcher shortcut owner.
- macOS Agenda uses private iCal subscriptions configured in **Manage Calendars**.
  The later Asyar Apple Calendar/EventKit adapter (`ical-guy`) is not ported.
  Do not publish a calendar just to enable the extension. If private feed access
  is unavailable, use Apple Calendar and defer launcher integration.
- Test recurring-event exceptions, cancelled/declined meetings, refresh, and
  meeting links rather than assuming Asyar's later bug fixes carry over.
- Configure Gemini credentials privately and test selected/clipboard input,
  preview, copy, and paste. Never commit API keys or calendar feed URLs.
- On macOS, test Rectangle-backed layouts and BetterDisplay brightness changes
  against the intended display; both companion apps must remain installed.
- Asyar's custom system theme-toggle extension is not ported. Use macOS
  appearance controls or Darkman's existing controls on NixOS.
- Previous macOS window-management findings are recorded in
  [the historical evaluation](vicinae-macos-evaluation.md), not assumed fixed.

## Recovery

Keep backups until the replacement has been verified on both machines. If a
build fails, do not activate. If runtime testing fails, return to the previous
system generation using your normal rollback procedure, or restore the Asyar
configuration in a focused follow-up change and rebuild. User-owned settings
and Homebrew apps are not fully rolled back by switching Nix generations.
Restore any removed app data from the archive only after quitting the relevant
app and checking for newer settings; do not overwrite newer data blindly.
