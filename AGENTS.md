# NixOS Configuration Agent Guidelines

## Build & Test Commands
- **Build system:** `nh os switch ~/nixos-config` (uses [nh](https://github.com/nix-community/nh) for better output)
- **Test configuration:** `nix build .#nixosConfigurations.framework.config.system.build.toplevel --dry-run`
- **Check flake:** `nix flake check`
- **Format code:** `nix fmt -- --check .` (auto-formatted on commit via pre-commit hooks)
- **Update flakes:** `nix flake update`

## Code Style Guidelines
- **Formatting:** Uses `nixfmt-rfc-style` - automatically applied via pre-commit hooks
- **File structure:** Modular organization with clear separation (modules/, home-manager/, hosts/)
- **Imports:** Use relative imports within modules, absolute paths for cross-module imports
- **Naming:** kebab-case for files, camelCase for variables where appropriate
- **Comments:** Minimal inline comments, prefer self-documenting code
- **Error handling:** Use proper Nix attribute set validation and default values

## Development Workflow
- direnv automatically loads dev shell on directory entry
- Pre-commit hooks ensure all committed code is formatted
- Use `rebuild` function from zsh for convenient system rebuilding
- Test changes with dry-run builds before applying