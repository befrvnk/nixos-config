# Zen Browser + Noctalia (NixOS)

Zen uses the reviewed community styles from the pinned
`noctalia-dev/community-templates@7aae018927ae35d007734868388c34c901870f45`.
The source files are consumed verbatim, not copied into a custom color generator.
The NixOS integration is in `../noctalia/zen-browser.nix`; Darwin is unaffected.

## Ownership

- `default.nix` keeps the profile-aware launcher, desktop actions, extensions and
  privacy/password-manager policies. The launcher uses the Home Manager-configured
  beta package and still passes `-P "Default Profile"`. Do not replace it with the
  raw flake package: that bypasses the module's policy configuration.
- Nix owns `.zen/default/chrome/userChrome.css` and `userContent.css`, containing
  absolute imports of the writable generated styles.
- Noctalia renders the two upstream CSS templates to
  `~/.local/state/noctalia/zen-browser/zen-userChrome.css` and `zen-userContent.css`.
  State storage keeps imported files available after cache cleanup.
- The shared activation preparer seeds valid CSS placeholders before imports are
  linked, safely privatizes protected legacy output with backups, and leaves
  writable generated colors alone during later Home Manager activations.
- `newtab-layout.css` preserves the existing 82px/64px responsive logo sizing,
  independently of palette colors. Upstream owns the color rules, including Glance.
- The required `toolkit.legacyUserProfileCustomizations.stylesheets` preference is
  enabled through package policies. Privileged developer tools are not enabled.

## Why the community apply hook is not used

Upstream's hook scans every profile with `prefs.js` under `.zen`/XDG Zen roots,
including old and backup profiles. It writes through CSS symlinks and rewrites
`user.js`, without backups. That is incompatible with these Nix-managed imports.

Only the two reviewed stylesheet inputs are registered as declarative user templates.
There is no `post_hook`, profile scan, `user.js` change, profile migration or browser
restart command. Do not additionally enable the mutable Zen community catalog entry
in the GUI: that would reintroduce the unsafe hook alongside the Nix registrations.
Current GUI template overrides were checked and do not enable a duplicate.
Other profiles, cookies, sessions, credentials and preferences
are not edited by the renderer. Existing browser policy declarations are retained;
tests check their actual presence in the packaged browser.

## Appearance and reload

Both generated files contain dark/light palettes selected by `prefers-color-scheme`.
Noctalia owns the system appearance preference; Darkman is not involved.
Mode switching and palette replacement are different tests: changing mode can
select existing CSS through media queries, but changed palette files may require
a full browser restart. No live reload is promised and the agent never closes Zen.

The template primarily styles browser chrome and internal pages, not complete
website themes. It also has global content accents (selection/form controls).
The upstream README warns that coverage of `about:logins`/`about:protections` is
not guaranteed. Those are upstream limitations, not reasons to fork the theme here.

## Test after rebuilding

```sh
rebuild switch -- --option substitute false
```

Select a noticeably different Noctalia palette, save work and fully quit/reopen
Zen using the existing launcher. Check the toolbar/sidebar and `about:newtab` or
`about:preferences`; then test light/dark separately. Confirm the expected profile,
extensions and 1Password behavior remain intact. `about:policies` can show active
policies. Report whether another palette change refreshes live or needs a restart.

Tests render two palettes in both modes, check immutable profile imports, unrelated
profile/preferences/backups remaining untouched, bootstrap/legacy-output handling,
non-color layout, and actual packaged policies/launcher selection. They do not
start Zen or validate CSS with Gecko. The user rebuilt and confirmed the integration
works. Live inspection verified protected imports, writable output and healthy
shell/overview services; detailed extension/profile and live reload behavior were
not independently instrumented by the agent.
