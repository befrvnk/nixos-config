# Overlay to add local idea-community package
# This provides IntelliJ IDEA (unified edition) from JetBrains CDN
final: prev: {
  idea-community = final.callPackage ../pkgs/idea-community/package.nix { };
}
