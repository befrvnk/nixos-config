# Umbriel Alt+Tab window switcher

**Status (2026-11-16): root cause found; fixed in the pinned Noctalia source, pending a
live test.** Alt+Tab opens the Noctalia switcher and Tab cycles, but Enter and releasing
Alt did not focus the selected window. Escape closes the overlay without switching.

## Root cause (2026-11-16)

Noctalia 5.3.0 sent Umbriel an IPC request that the current Umbriel build rejects:

- Noctalia: `{"cmd":"msg","arg":"window-focus-warp:<id>"}`. Umbriel replies
  `unknown command: msg`.
- Umbriel's CLI (`umbriel msg window-focus-warp <id>`, traced with `strace`) sends
  `{"action":"window-focus-warp","cmd":"action","window":"<id>"}`.

Noctalia logs nothing when the request fails, so the symptom was silent. Upstream fixed
the sender in commit `48137bd` ("send compositor actions as typed IPC requests"), which
is included in `v5.5.0`. The pinned commit `c1a7283` includes it and the patch set is
verified against it. Because the old 5.3.0 sender is gone, the fix only needs the pin.
The live test is still pending: Enter should focus the selected window and releasing Alt
should commit the selection.

The trial notes said Alt+Tab was user-confirmed during the trial (see
[umbriel-trial.md](umbriel-trial.md)). The regression was first reported on
2026-11-14 at the current pin. It was not bisected.

## Symptoms

| Action | Result |
| --- | --- |
| Alt+Tab opens the overlay | Works |
| Tab cycles the selection | Works |
| Release Alt | Does not switch; overlay stays on the current selection |
| Enter | Does not switch |
| Escape | Closes the overlay, no switch (works) |

## Versions

- Umbriel `0c1f125` (2026-11-11 commit), locked on 2026-11-12 by `149bb98`.
  Previous lock: `c6ad18d`. Umbriel `0.1.0`.
- Noctalia `5.3.0`, the pinned native shell.

## Configuration

- `home-manager/nixos/umbriel/binds.nix`: Alt+Tab was originally
  `spawn noctalia msg window-switcher hold`.
- Attempt 1 (no effect): `Alt_L` and `Alt_R` release binds running
  `window-switcher close`. `close` only hides the overlay and does not change focus.
  Umbriel's keybind docs say a matched release bind consumes its press and release,
  so these binds also swallow Alt for other applications. Removed.
- Attempt 2 (no effect): `general.focus_on_activate = true` as a runtime override.
  Reverted to the default `false`.
- Current state at time of writing: Alt+Tab runs `window-switcher` without `hold`
  (uncommitted in the working tree).

## Evidence

- `umbriel msg window-focus-warp <window-id>`, with a valid id from
  `umbriel windows --json`, moved focus. It also worked while the overlay was open,
  opened with `noctalia msg window-switcher`. An unknown id returns
  `unknown window: <id>`, so the action is parsed.
- Umbriel's journal logs each `window-switcher` launch and config reloads. It logs
  nothing about focus or activation.
- Noctalia's journal at debug level (`noctalia msg log-level-set debug`) logs no
  switcher lines. Failed IPC requests are silent.

## Code path (Noctalia 5.3.0)

When Enter is pressed:

1. `WindowSwitcher::activateSelected()` in `src/shell/switcher/window_switcher.cpp`
   calls `hide()`, then schedules `activateWindowSwitcherEntry()` with `DeferredCall`.
2. On Umbriel with a non-empty `windowId`, `activateWindowSwitcherEntry()` calls
   `focusCompositorWindow(id, true)` in `src/compositors/compositor_platform.cpp`.
3. That calls `focusWindowById()` in
   `src/compositors/umbriel/umbriel_workspace_backend.cpp`, which sends the
   `window-focus-warp` action via `UmbrielRuntime::requestAction()` in
   `src/compositors/umbriel/umbriel_runtime.cpp`.

`requestAction()` returns only a bool, and the failure is not logged. The
failing step is either the request itself, or the `windowId` Noctalia holds for
the selected entry.

## Ruled out or unverified

- Umbriel blocking focus while the overlay holds the keyboard: ruled out by the
  test above.
- fcitx5: not running. Noctalia issue #4583 needed it.
- `focus_on_activate`: not on this path. Umbriel issue #204 is about activation
  requests from other applications.
- Unverified: whether the id Noctalia holds for each entry matches Umbriel's
  `windows` ids in practice, and whether the request is sent at all.

## Related upstream reports

- `noctalia-dev/noctalia#4583` (closed): on Umbriel the switcher got `modifier=0`
  and switched without showing the overlay. The maintainer says a later Umbriel build
  fixed it. Different symptom, same area.
- `noctalia-dev/noctalia#5271` (open): switcher option bug on Mango. Unrelated.
- `noctalia-dev/umbriel#204` (open): `focus_on_activate` is not honored for some
  clients. Not on this path.
- No issue found that reports Enter or release not focusing on Umbriel, as of
  2026-11-14. Not yet reported upstream.

## Workarounds not applied

- `window-focus-last`: toggles between the last two windows.
- `window-focus-next` and `window-focus-previous`: cycle focus with no overlay.
  Their exact scope (per workspace or across outputs) is not verified.

Both use Umbriel actions that are known to work, but they drop the overlay.

## Reopen when

- An upstream issue or fix appears for Enter or release focusing on Umbriel.
- The owner asks to resume.

Next diagnostic step: find a way to log the `window-focus-warp` reply Noctalia
receives, or the window id it holds for the selected entry.
