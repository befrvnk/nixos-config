{ pkgs, ... }:
{
  # IntelliJ IDEA (unified edition) from JetBrains CDN
  # Plugins (NixIDEA, Auto Dark Mode, etc.) can be installed via IDE settings.
  # Update with: ./scripts/update-idea-community.sh
  home.packages = [
    pkgs.idea-community
  ];
}
