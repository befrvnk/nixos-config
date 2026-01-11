{
  pkgs,
  inputs,
  lib,
  ...
}:

let
  # Get IDE version for plugin lookup (e.g., "2025.3.1" -> "2025.3")
  ideaVersion = lib.versions.majorMinor pkgs.jetbrains.idea-oss.version;

  # IntelliJ IDEA Open Source with NixIDEA plugin pre-installed
  # Other plugins (Auto Dark Mode, Claude Code) can be installed manually via IDE
  # Note: idea-community is deprecated, use idea-oss (built from source) instead
  ideaWithPlugins = pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.idea-oss [
    inputs.nix-jetbrains-plugins.plugins.${pkgs.system}.idea-community.${ideaVersion}.nix-idea
  ];
in
{
  home.packages = [
    ideaWithPlugins
  ];
}
