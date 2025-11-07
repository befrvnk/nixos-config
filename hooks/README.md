# Git Hooks

This directory contains git hooks for the nixos-config repository.

## Pre-commit Hook

The pre-commit hook automatically formats all staged `.nix` files using `nixfmt` before each commit. This ensures consistent code formatting across the repository.

### Installation

To install the pre-commit hook, run:

```bash
./hooks/install.sh
```

This will copy the pre-commit hook to `.git/hooks/` and make it executable.

### Prerequisites

The pre-commit hook requires `nixfmt` to be installed. You can install it using:

```bash
nix-env -iA nixpkgs.nixfmt-rfc-style
```

Or, if you're using this repository's development shell:

```bash
nix develop
```

### How It Works

When you run `git commit`:

1. The hook identifies all staged `.nix` files
2. Formats each file using `nixfmt`
3. Re-stages the formatted files
4. Proceeds with the commit

If `nixfmt` is not installed, the hook will fail with an error message.

### Uninstallation

To remove the pre-commit hook:

```bash
rm .git/hooks/pre-commit
```

## Development Shell

This repository also includes a Nix development shell with pre-commit-hooks integration. When you enter the shell with `nix develop`, the hooks will be automatically installed and managed.
