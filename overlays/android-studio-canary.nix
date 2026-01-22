# Override Android Studio Canary with latest version
# nixpkgs-unstable doesn't update Android Studio Canary frequently enough
# This overlay provides the latest canary version from Google
#
# Update with: ./scripts/update-android-studio-canary.sh
final: prev:
let
  versionInfo = import ../pkgs/android-studio-canary/version.nix;

  # Replicate nixpkgs mkStudio pattern
  # common.nix is a function that takes opts and returns another function for callPackage
  mkStudio =
    opts:
    final.callPackage (import "${prev.path}/pkgs/applications/editors/android-studio/common.nix" opts) {
      fontsConf = final.makeFontsConf { fontDirectories = [ ]; };
      inherit (final) buildFHSEnv;
      tiling_wm = true; # Enable for niri compatibility
    };
in
{
  androidStudioPackages = prev.androidStudioPackages // {
    canary = mkStudio {
      channel = "canary";
      pname = "android-studio-canary";
      inherit (versionInfo) version;
      sha256Hash = versionInfo.hash;
    };
  };
}
