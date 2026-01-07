# direnv configuration
#
# direnv is a shell extension that automatically loads and unloads environment
# variables based on the current directory. It integrates seamlessly with Nix
# development shells.
#
# How it works:
# - When you cd into a directory with a .envrc file, direnv automatically executes it
# - When you cd out, it unloads the environment
# - Also works when opening a terminal directly in a directory with .envrc
#
# For this nixos-config repository:
# - The .envrc file contains "use flake"
# - This automatically runs "nix develop" when entering the directory
# - The dev shell installs pre-commit hooks for nixfmt
# - No manual commands needed - everything is automatic
#
# Security:
# - direnv requires explicit approval (direnv allow) before loading a new .envrc
# - This prevents arbitrary code execution from untrusted directories

{ ... }:

{
  programs.direnv = {
    enable = true;

    # Enable nix-direnv for faster, cached nix shell loading
    # This caches the Nix development shell to make subsequent loads instant
    nix-direnv.enable = true;

    # Automatically enable direnv in bash (fallback shell)
    enableBashIntegration = true;

    # Automatically enable direnv in nushell
    enableNushellIntegration = true;
  };
}
