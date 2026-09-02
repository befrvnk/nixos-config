# Override Android Studio Canary with latest version
# nixpkgs-unstable doesn't update Android Studio Canary frequently enough
# This overlay provides the latest canary version from Google
#
# Update with: ./scripts/update-android-studio-canary.sh
{ nixpkgsSrc }:
final: prev:
let
  versionInfo = import ../pkgs/android-studio-canary/version.nix;

  mkStudio =
    opts:
    final.callPackage (import "${nixpkgsSrc}/pkgs/applications/editors/android-studio/linux.nix" opts) {
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
      meta = prev.androidStudioPackages.canary.meta;
      sources.x86_64-linux = {
        inherit (versionInfo) url;
        sha256Hash = versionInfo.hash;
      };
    };
  };
}
