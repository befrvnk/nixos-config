# Origin rebase validation — 2026-10-22

## History and dependency policy

Rebased the 31 local Noctalia migration commits onto fetched `origin/main` at
`a44373c`. The original tip was `9a4190b`; the replayed native-idle checkpoint is
`f7b1b5b`. All replayed commits were signed and their signatures verified.

The pre-rebase branch is retained locally as
`backup/noctalia-before-origin-rebase-20261022-134245`. No remote history was pushed.

For `flake.lock`, preserve every origin node and existing root input reference.
Graft only the local-only Noctalia, community-plugin/template and retained legacy
Quickshell/QML inputs, renaming node IDs where they collide. Graph names are not
versions: all origin locked metadata and root edges, and all local-only source
pins, were compared programmatically. Nix accepts the graph without updating it.
Other tracked dependency locks, including `devenv.lock` and npm locks, match origin.
No general flake update or dependency rollback was used to make checks pass.

Origin's newer nixpkgs/Home Manager/Stylix/Vicinae pins are retained. Noctalia itself
remains intentionally pinned to V5.3.0 (`a33122c`): origin did not define that local
input. Its own nixpkgs remains independent for upstream cache compatibility.

## Merge and compatibility review

- Preserve origin's new launcher/package work, shared cliamp, Darwin configuration,
  Atuin integration and additional NixOS packages.
- Preserve origin's moved GTK/Papirus ownership in `stylix.nix`. Do not restore its
  static Kvantum Qt configs over the native Qt5ct/Qt6ct palette configs. Native Qt
  remains Fusion with the configured fonts and icons.
- New Stylix ties cursor projection to target enablement. With native GTK and
  Xresources colors, those targets are disabled. Keep the cursor name/package/size
  explicit in the native modules; existing retention invariants caught the missing
  settings before the fix.
- Origin's Pi 1.3.0 native Linux X11 addon requires `libxcb.so.1`. Declare libxcb in
  Linux build inputs rather than suppressing autoPatchelf errors, changing versions
  or altering source hashes. The package and offline package/extension smoke checks
  pass with this dependency. Darwin's build inputs are unchanged.
- Both `lockscreen-pam-service.patch` and `suspend-lock-policy.patch` apply to the
  resolved Noctalia source with `--fuzz=0`, without offsets. The actual configured
  package remains patched. No PAM algorithm or fingerprint policy was changed.
- Vicinae 0.29.2 still rescans/reloads an already-selected theme without writing
  settings. Keep both selectors `noctalia` and the immutable HM override wrapper.
  Its common headers moved to `src/lib/common/include`; add that include path to
  the real parser probe, which now compiles and passes against the newly pinned
  source. Do not substitute a fixture parser or drop the regression tests.
- The updated Framework kernel compiled, but main nixpkgs' module aggregator then
  required `modules.cer` that CachyOS's independently pinned builder does not emit.
  Framework now selects that provider's matching aggregateModules helper only for
  a CachyOS kernel built with the provider's stdenv. Standard-kernel selection
  retains main nixpkgs' certificate-aware helper; both dispatch branches were
  evaluated. The correction fabricates no empty certificates, does not modify the
  already-compiled kernel/module bytes, retains the Keychron battery module and
  disables no signature-verification options.
  The provider's existing `CONFIG_MODULE_SIG`-unset configuration is unchanged:
  this compatibility fix does not add module-signature enforcement. Secure Boot
  loader settings remain intact. Review this rule when changing the provider.
- The revoked Lantian cache URL/key remain excluded. This does not retroactively
  verify previously downloaded artifacts or kernel provenance.

Useful replayed checkpoint references:

| Checkpoint | Original | Rebased |
|---|---|---|
| Palette before runtime-controller handover | `3f51f68` | `77d6c20` |
| Cache-trust revocation | `1b014df` | `364d54b` |
| Password PAM preflight foundation | `4f39d5d` | `6e49d45` |
| Manual native lock trial | `849a1f2` | `1abddfe` |
| Native idle/automatic locking | `9a4190b` | `f7b1b5b` |

Older chronological notes retain their original hashes. Use the replayed references
or the backup branch when inspecting those checkpoints.

## Validation status

- Lock graph preservation and no-update metadata validation: passed.
- Strict patch application: passed.
- Formatting/statix for the 50 replayed Nix files and compatibility changes: passed.
- Safety-script ShellCheck (Bash specified for the sourced activation fragment): passed.
- Framework evaluation/dry run and theme/auth/cache assertions: passed after fixes.
- Hermi and macbook system derivation evaluation: passed. These are not native
  ARM/Darwin builds or runtime tests.
- Updated Pi package and offline smoke/extension checks: passed.
- All 139 Noctalia tests against the updated dependencies/real Vicinae parser: passed.
- All 17 x86_64-linux flake checks: passed, including 139 Noctalia tests and 19
  mocked suspend tests against the updated dependencies. The added lightweight
  kernel-provider compatibility check asserts both aggregation dispatch branches
  without requiring a kernel rebuild.
- Full Framework build, including CachyOS 6.18.52, module aggregation, initrd and
  Home Manager generations: passed. The already-compiled kernel was reused for
  the module-helper compatibility correction, not rebuilt with different flags.
- Pinned-provider versus standard-kernel aggregation dispatch evaluation: passed.
  The final module tree has its depmod map and the external Keychron module; the
  kernel output is exactly the compiled CachyOS output from before the helper fix.

## Activation boundary

No live configuration activation, application theme, authentication, lock, suspend,
fingerprint, volume or brightness action was performed by the agent. Do not count pre-rebase
live observations as tests of the updated system stack. After user activation while
unlocked, recheck native lock/password, idle registration/suspend, inhibitor handling
and cursor/theme integration before further cleanup.

The follow-ups in [the lock migration guide](noctalia-lockscreen-migration.md) remain
open, including the power-button wake interaction, extended inhibited-idle tests,
reader-unavailable password fallback and external-output coverage. Fallback
swaylock/PAM/style and the theme bridge/specialisations remain intact.
