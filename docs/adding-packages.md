# Adding Packages

This repo splits package ownership by scope and platform.

## Choose the Right Place

### System packages
Use `modules/system/packages.nix` for packages that should exist for every user or are needed by the system itself.

Examples:
- `git`, `wget`, `vim`
- boot/security tooling
- system daemons and shared utilities

Apply changes with:

```bash
rebuild switch
# or
nh os switch .
```

### Home Manager packages
Use Home Manager for user-facing tools and applications.

#### NixOS-only user packages
Add to:
- `home-manager/nixos/packages.nix`
- or the specific module that owns the tool

#### Darwin-only user packages
Add to:
- `home-manager/darwin/packages.nix`
- or the specific Darwin module that owns the tool

#### Cross-platform packages
Prefer putting the package in the shared module that configures it under:
- `home-manager/shared/`

Examples already following this pattern:
- `home-manager/shared/gh.nix`
- `home-manager/shared/navi/default.nix`
- `home-manager/shared/pi/default.nix`

## Package Ownership Rule

If a module configures a tool, that module should usually own the package too.

Good examples:
- `home-manager/shared/navi/default.nix` configures **and** installs `navi`
- `home-manager/shared/worktrunk.nix` configures **and** installs `worktrunk`

Use the catch-all package lists only when a tool has no dedicated module yet.

## Example: Add a simple CLI tool

### NixOS-only
Add it to `home-manager/nixos/packages.nix`:

```nix
home.packages = with pkgs; [
  bat
  fd
  your-new-package
];
```

### Darwin-only
Add it to `home-manager/darwin/packages.nix`:

```nix
home.packages = with pkgs; [
  bat
  fd
  your-new-package
];
```

### Shared module-owned tool
If the tool has configuration, create a shared module instead:

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.your-new-package ];

  programs.your-tool = {
    enable = true;
  };
}
```

Then import it from `home-manager/shared/default.nix`.

## Example: Add a new application module

### NixOS module
1. Create `home-manager/nixos/app.nix`
2. Import it from `home-manager/nixos/frank.nix`

```nix
imports = [
  ./app.nix
];
```

### Darwin module
1. Create `home-manager/darwin/app.nix`
2. Import it from `home-manager/darwin/frank.nix`

### Shared module
1. Create `home-manager/shared/app.nix`
2. Import it from `home-manager/shared/default.nix`

## Searching for Packages

```bash
nix search nixpkgs firefox
nix eval nixpkgs#firefox.meta.description
```

## Temporary Testing

```bash
nix run nixpkgs#firefox
nix shell nixpkgs#firefox nixpkgs#chromium
```

## Packaging Software Not in nixpkgs

Packages this repo maintains live in `pkgs/<name>/`, with a matching overlay in
`overlays/<name>.nix`.

### Scaffold with nix-init

`nix-init` (available in the devenv shell) generates a package expression with
hashes, dependencies, and license filled in:

```bash
nix-init https://github.com/owner/repo v1.2.3
```

It detects the right builder (`buildGoModule`, `buildRustPackage`,
`buildPythonApplication`, `stdenv.mkDerivation`, …) and prompts for the rest.
Review the generated `meta` block before committing — description, license, and
`mainProgram` are guesses.

For the hash on its own, `nurl` prints a ready-to-use fetcher:

```bash
nurl https://github.com/owner/repo v1.2.3
```

### Wire the package up

1. Put the expression in `pkgs/<name>/package.nix`.
2. Create `overlays/<name>.nix`:
   ```nix
   final: prev: {
     name = final.callPackage ../pkgs/name/package.nix { };
   }
   ```
3. Import the overlay in the matching list in `lib/overlays.nix`:
   - `sharedOverlays` for both platforms
   - `nixosOverlays` or `darwinOverlays` for one platform only

Add the package to `modules/system/packages.nix` or a Home Manager module — see
the ownership rule above.

### Add an update script

For packages that track GitHub releases, follow the existing scripts:

1. Create `scripts/update-<name>.sh` sourcing `update-common.sh` (see
   `scripts/update-gh-enhance.sh`). It uses `nurl` for the source hash and falls
   back to `nix-prefetch-url` when nurl is unavailable.
2. Call it from the `flake-update` command in `devenv.nix`, next to the other
   `./scripts/update-*.sh` lines.

## Rebuild Commands

### NixOS
```bash
nh os switch .
# or
rebuild switch
```

### Darwin
```bash
nh darwin switch .
```

## Notes

- Use `nix fmt` after edits
- Use `statix check .` for Nix linting
- Prefer module-owned packages over growing the catch-all package lists
- GUI apps on macOS may belong in `hosts/macbook-darwin/default.nix` under Homebrew instead of nixpkgs
