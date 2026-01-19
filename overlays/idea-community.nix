# Overlay to add local idea-community package
# This provides IntelliJ IDEA Community from GitHub releases
final: prev: {
  idea-community = final.callPackage ../pkgs/idea-community/package.nix { };
}
