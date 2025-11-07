#!/usr/bin/env bash

# Installation script for git hooks
# This script installs the pre-commit hook to automatically format Nix files

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_HOOKS_DIR="$(git rev-parse --git-dir)/hooks"

echo "Installing pre-commit hook..."

# Copy the pre-commit hook
cp "$SCRIPT_DIR/pre-commit" "$GIT_HOOKS_DIR/pre-commit"

# Make it executable
chmod +x "$GIT_HOOKS_DIR/pre-commit"

echo "Pre-commit hook installed successfully!"
echo ""
echo "The hook will automatically format all staged .nix files with nixfmt before each commit."
echo "Make sure nixfmt is installed: nix-env -iA nixpkgs.nixfmt-rfc-style"
echo ""
echo "To uninstall, simply remove: $GIT_HOOKS_DIR/pre-commit"
