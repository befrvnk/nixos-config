# Nix Configuration Agent Guidelines

Multi-platform: **NixOS** (Framework laptop) and **macOS/Darwin** (MacBook Pro M4).

## Build & Test Commands

**AI Agents:** Do NOT run `sudo` commands. Ask user to run manually.

| Task | NixOS | Darwin |
|------|-------|--------|
| Rebuild | `rebuild switch` or `nh os switch .` | `nh darwin switch .` |
| Test (no boot) | `nh os test .` | N/A |
| Build only | `nh os build .` | `nh darwin build .` |
| Update + rebuild | `nix flake update && rebuild switch` | `nix flake update --accept-flake-config && nh darwin switch .` |
| Cleanup | `nh clean all --keep 5` | `nh clean all --keep 5` |
| Check flake | `nix flake check --accept-flake-config` | `nix build .#darwinConfigurations.macbook.system --dry-run --accept-flake-config` |
| Format | `nix fmt` | `nix fmt` |
| Lint | `statix check .` | `statix check .` |

**Notes:**
- Always use `--accept-flake-config` flag with nix commands (trusts cachix)
- `nix flake check` evaluates ALL configs - use dry-run build on Darwin
- Devenv scripts (`rebuild`, `check`) include flags automatically
- Avoid legacy: `nixos-rebuild`, `nix-collect-garbage` → use `nh` instead

**Safe for agents:** devenv scripts, nh commands, nix commands with flags, git operations, `systemctl --user`, file operations.

**Requires sudo (DO NOT RUN):** rollback, hardware scans, system services.

## Code Style

- **Formatting:** `nixfmt` (RFC style) via pre-commit hooks
- **Naming:** kebab-case files, camelCase variables
- **Sorting:** Alphabetize imports and lists
- **Scripts:** Externalize >5 lines to `.sh` files, use `pkgs.writeShellScript` with explicit PATH
- **Merging:** Prefer `lib.mkMerge` for readability
- **Comments:** Minimal, prefer self-documenting code

### Nushell
Default shell on NixOS. Key differences from bash:
- Chain with `;` not `&&` (logical AND in Nushell)
- Environment: `$env.VAR` not `$VAR`
- No `&` for background - use `bash -c "cmd &"`

## Development Workflow

1. Read existing code before modifying
2. Make changes
3. Test: `nh os test .` (NixOS) or `nix flake check --accept-flake-config` (Darwin)
4. Lint: `statix check .` for Nix, `shellcheck` for scripts
5. Apply: `rebuild switch` (NixOS) or `nh darwin switch .` (Darwin)
6. Update docs if needed
7. Commit with descriptive message

## Project Structure

```
nixos-config/
├── flake.nix              # Entry point
├── lib/                   # mkHost, mkDarwinHost builders
├── hosts/
│   ├── framework/         # NixOS (hardware-configuration.nix, home.nix)
│   └── macbook-darwin/    # Darwin (all-in-one default.nix)
├── modules/               # NixOS system modules only
│   ├── desktop/hardware/services/system/theming/
├── home-manager/
│   ├── nixos/             # NixOS-specific (niri/, ironbar/, stylix.nix)
│   ├── darwin/            # Darwin-specific (ghostty, packages)
│   └── shared/            # Cross-platform (git, starship, atuin, ssh)
├── overlays/              # Package modifications
├── shared/themes.nix      # Central base16 theme definitions
└── docs/                  # Detailed guides
```

See subdirectory CLAUDE.md files for detailed patterns:
- `modules/CLAUDE.md` - NixOS system module patterns
- `home-manager/CLAUDE.md` - Home-manager organization
- `home-manager/nixos/CLAUDE.md` - NixOS-specific gotchas (audio, power, theming)
- `home-manager/darwin/CLAUDE.md` - Darwin-specific gotchas
- `hosts/CLAUDE.md` - Host configuration patterns

## Module System
- `lib.mkForce` - highest priority override
- `lib.mkDefault` - lowest priority default
- `lib.mkMerge` - combine attribute sets
- `lib.mkIf` - conditional config
- `lib.mkBefore/mkAfter` - order list items

## Path References
- **Nix store:** `${pkgs.tool}/bin/tool`
- **Relative imports:** `./file.nix`
- **Cross-module:** `../../path/to/module`
- **Home directory:** `config.home.homeDirectory` (NixOS: `/home/frank`, Darwin: `/Users/frank`)

## Git Commits

Format: `<type>: <summary>`

Types: Add, Update, Fix, Refactor, Remove, Document

Good: `Add battery monitoring with event-driven alerts`
Bad: `Update config`

Commit after each logical change that builds. Related changes in one commit.

## Pre-commit Hooks

- `nixfmt` runs automatically on commit
- Manual: `nix fmt`
- Skip (emergency only): `git commit --no-verify`
- If hook fails: fix file, stage, commit again

## Documentation

Update docs when making changes:
1. README.md - user-facing features
2. docs/ - detailed technical guides
3. CLAUDE.md files - patterns and gotchas

Detailed guides in docs/:
- structure.md, adding-packages.md, new-host.md
- secure-boot.md, fingerprint-setup.md (NixOS)
- stylix-darkman-setup.md, ironbar-niri-overview.md (NixOS)
- macbook-darwin-setup.md (Darwin)

## Common Gotchas (All Platforms)

- **State versions:** Never change (NixOS: `25.05`, Darwin system: `5`)
- **Home directory:** Use `config.home.homeDirectory` for portability
- **opencode bun version:** The opencode flake has an overly strict bun version check (`^1.3.10`) that fails with nixpkgs' bun 1.3.9. Workaround in `lib/darwin.nix` patches it out via `overrideAttrs`. Remove once [anomalyco/opencode#8469](https://github.com/anomalyco/opencode/issues/8469) is fixed upstream.
