{ pkgs, ... }:
{
  # IntelliJ IDEA Community Edition from GitHub releases
  # JetBrains discontinued IDEA Community on their CDN in July 2025,
  # but continues publishing pre-built binaries to GitHub releases.
  # Plugins (NixIDEA, Auto Dark Mode, etc.) can be installed via IDE settings.
  # Update with: ./scripts/update-idea-community.sh
  home.packages = [
    pkgs.idea-community
  ];
}
