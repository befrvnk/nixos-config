# Override Android Studio Canary with latest version
# nixpkgs-unstable doesn't update Android Studio Canary frequently enough
# This overlay provides the latest canary version from Google
#
# Update with: ./scripts/update-android-studio-canary.sh
final: prev:
let
  versionInfo = import ../pkgs/android-studio-canary/version.nix;
in
{
  androidStudioPackages = prev.androidStudioPackages // {
    canary = prev.androidStudioPackages.canary.overrideAttrs (old: {
      version = versionInfo.version;
      src = prev.fetchurl {
        url = "https://dl.google.com/dl/android/studio/ide-zips/${versionInfo.version}/android-studio-${versionInfo.version}-linux.tar.gz";
        hash = versionInfo.hash;
      };
    });
  };
}
