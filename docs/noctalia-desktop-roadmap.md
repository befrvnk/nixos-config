# Next Noctalia desktop changes

Owner priorities (2026-10-23), in this order:

1. **Noctalia Greeter** replaces the current tuigreet frontend.
2. **Umbriel trial**, initially alongside Niri rather than deleting the working session.
3. **Noctalia topbar UI**, after the compositor decision so UI work targets its real
   overview/workspace behavior.

These supersede ordinary cleanup as the immediate next work. The
[owner-deferred backlog](noctalia-backlog.md) stays deferred.

## 1. Greeter — password login and keyring handoff accepted

Noctalia Greeter is a frontend for **greetd**, not a replacement daemon. The pinned
nixpkgs already provides Greeter 1.7.0 and its NixOS module; no new input, dependency
update or Umbriel installation is needed for this step. Its login-screen compositor
is packaged with the greeter, distinct from the user's later compositor trial.

Use the native NixOS module, keep the greeter account and Niri session, and preserve
the existing login/TTY/sudo/polkit/swaylock/native-lock PAM and keyring/session setup.
The follow-up below intentionally changes only greetd's authentication phase.
The current custom us-umlauts XKB layout and NixOS desktop-entry search paths need
explicit handling in the greeter process; do not silently fall back to plain US or
assume /run/current-system/sw/share/wayland-sessions exists.

Keep greeter.toml declarative and sync.toml writable. Appearance sync keeps the
normal administrator prompt; no passwordless rule or automatic sync is authorized
by the frontend change alone. Start with upstream appearance defaults rather than
bundling topbar/theme redesign into login migration.

The owner chose **password as the default**, with one initial authentication.
auth.allow_empty_password=false requires password input before starting PAM, but the
first trial showed this frontend flag alone was insufficient: PAM authenticated
through the inherited fingerprint stack before consuming the typed password.

The fix replaces only greetd's auth rules, conditionally when Noctalia
Greeter is enabled, with required pam_unix (no nullok/permit) followed by optional
pam_gnome_keyring. The password must actually authenticate before success, and the
same PAM token is cached for keyring unlock. Both the inherited login-auth substack
and direct greetd fingerprint rules are excluded; merely disabling the latter would
still leave inherited fingerprint authentication. Greetd account/password/session
stanzas continue to include/substack login unchanged. Native-lock/TTY/login/sudo/
polkit/swaylock and fprintd/lid policy are untouched.

This intends one login password reused to unlock a matching Login keyring. It does
not make keyrings unencrypted, save credentials in Nix/environment/files, change
keyring passwords, or suppress legitimate later Polkit/1Password prompts. A
separately different keyring password can still require investigation; never erase
the store or blank its password to hide an unlock problem.

### Validation completed

- Full Framework build and all 18 Linux checks pass (172 native Noctalia tests,
  19 mocked suspend tests, plus the expanded 8-test Greeter check).
- Initial UI-only draft preserved all six PAM files, which exposed the undesirable
  fingerprint/keyring flow in the live trial. The fix intentionally changes only
  greetd auth: exact required-unix/optional-keyring order is checked with no nullok,
  permit, fingerprint or auth include/substack. Remaining greetd sections compare
  unchanged against the integration-disabled reference. The other five PAM files
  remain byte-for-byte equal to that reference and the currently deployed files;
  a separate live-file comparison also confirmed greetd's non-auth rows unchanged.
- Actual installed Greeter `sessions` CLI discovers Niri using the scoped data path;
  source-reviewed early CLI dispatch exits before Wayland/auth initialization.
- Actual libxkbcommon compiles the custom layout and verifies normal A and Right
  Alt+A/O/U umlauts in an isolated keymap, without any device/compositor connection.
- Private fake-frontend probes execute the rendered environment wrapper; real
  Greeter/session/compositor launch and authentication are never run by the agent.
- Formatting, statix and Nix diagnostics pass; no input/lock/cache changes.

The first user reboot rendered Noctalia Greeter and successfully launched Niri.
At 15:50:32 the Greeter started PAM and received a fingerprint instruction, with
success at 15:50:36. GNOME Keyring SystemPrompter requested a password at 15:50:37;
the default collection unlocked at 15:50:42 after the user entered it. These logs
identify a keyring prompt, not Greeter appearance sync or a generic Polkit request.

The user then rebooted with the scoped PAM fix and reported success. On that boot
at 16:07:25, Greeter logs show a Password secret prompt followed by successful
authentication and Niri session startup, with no fingerprint instruction. Greetd
logged the password cached until open_session, then gnome-keyring-daemon started
and unlocked the keyring. The preliminary missing-control-file message was followed
by that successful handoff, not an unresolved failure. Native Noctalia immediately
reported its default Secret Service collection unlocked, without a separate startup
keyring prompt. Greetd/HM succeeded, native/overview remained active, the theme worker
finished normally with its path waiting, and no failed user units remained.

Accept the user-observed single-password login and automatic keyring handoff on this
boot. Appearance sync, a negative-password UI challenge and all-output rendering are
not certified by that success. Backlogged reader/output/power checks stay deferred.
The agent only built/checked and read focused status/logs; no activation, authentication,
fingerprint scan or service restart was performed by the agent.

### User-only cutover (trial completed; retain for future changes)

1. Save work. Keep the existing TTY/password recovery route and previous boot
   generation available. Do not clean old generations during the trial.
2. Run **bare `rebuild`**, which defaults to `nh os boot` on this host, or explicitly
   `nh os boot --accept-flake-config .`. Do not use `rebuild boot`: that helper only
   special-cases `switch` and otherwise forwards arguments to nh.
3. Reboot yourself when ready. Do not restart greetd inside the working session.
   The NixOS unit retains restartIfChanged=false, but boot-only staging is clearer
   for this login-manager trial than relying on a live-switch lifecycle.
4. Confirm the graphical Noctalia Greeter appears and Niri is selected. Select your
   account, enter your password privately and log in. Do not send credentials to
   the agent. Greetd's password-only auth should not request a fingerprint.
5. Confirm Niri/Noctalia starts without a second Login-keyring unlock dialog, and
   keyboard layout is usable; report only outcomes or nonsensitive error text. Don't
   test the reader-unavailable/output/power-button backlog as part of this change.

If the Greeter does not render or login fails, use the known TTY recovery route or
boot the previous working generation from the boot menu. Avoid repeated failed
logins, changing PAM, or blindly restarting greetd. Agent checks afterward are
read-only: greetd/native/HM status, focused boot logs and configured session/state.

### Appearance and state

The native module owns /var/lib/noctalia-greeter/greeter.toml via a store-backed
L+ tmpfiles entry and prepares the directory as greeter-owned 0750. Mutable UI/sync
state belongs in sync.toml, not the managed file. The Greeter's own packaged private
compositor renders login; neither Niri nor Umbriel is used to render the greeter.

After the login baseline passes, the user may optionally run Noctalia Settings →
Security → Noctalia Greeter → Sync Now. It retains the administrator prompt; the
agent never invokes sync or grants passwordless access. Appearance remains unpinned
so authorized sync is not shadowed by a declarative wallpaper/scheme. Automatic
sync is not enabled by this change. Topbar UI remains a later separate step.

## 2. Niri and Umbriel — both retained for user experiments

The [Umbriel trial guide](umbriel-trial.md) records the pins, preserved behavior,
explicit mapping differences, checks and user-only entry/recovery. It uses the
already-pinned nixpkgs module/package and matching portal; no new input, lock update,
cache trust or kernel change. Greeter keeps Niri as default and offers Umbriel as
an additional session. Niri's actual config and all six deployed PAM files remain
unchanged. No compositor or hardware action was performed by the agent.

Full Framework build and all 19 Linux checks pass: 177 Noctalia, 11 Umbriel, 8 Greeter
and 19 mocked suspend tests. User entry/basic smoke passed and passive checks found
healthy Umbriel/native/overview services, but detailed visual/input/lock/portal/power/
session-return coverage remains unverified. Missing Alt+Tab was a binding omission;
its native Noctalia hold-switcher follow-up is installed and user-confirmed working,
with valid reload and no compositor/native-service restart. Native session lifecycle is retained;
Home Manager/Nushell environment and custom XKB readiness are handled by the scoped
launcher, and the existing overview adapter supports the active compositor.

Read the keybinding differences before user entry. Do not treat a valid config as
full Niri parity or retirement authorization. The reader/output/power backlog stays
deferred. The owner chose to keep both sessions and experiment with performance/
behavior differences when convenient. Niri stays the configured default; do not
remove either, select a winner automatically or require another comparison now.
Optional A/B work is tracked in backlog NOC-04. Alt+Tab's normal live behavior is
accepted; do not extend that to broader performance/security or unreported cases.

## 3. Topbar — next separately requested UI step, supporting both

The dual-session decision is sufficient to discuss topbar UI without choosing one
compositor permanently. Collect the desired changes from the owner first; no UI
redesign is authorized by the keep-both request alone. Preserve both overview-only
adapters, existing widgets/bindings/layout and Niri recovery unless explicitly changed.

## References reviewed

- [Greeter installation and native NixOS module](https://docs.noctalia.dev/greeter/installation/)
- [Greeter configuration and authentication UX](https://docs.noctalia.dev/greeter/configuration/)
- [Appearance sync/authorization](https://docs.noctalia.dev/greeter/sync/)
- [Umbriel installation and NixOS integration](https://docs.noctalia.dev/umbriel/installation/)

Official current docs are guidance; pinned nixpkgs/Greeter source remains the
implementation authority for this configuration.
