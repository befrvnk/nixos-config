{ pkgs-unstable, android-nixpkgs, ... }:

{
  # Import the android-nixpkgs Home Manager module to make the options available
  imports = [ android-nixpkgs.hmModule ];

  home.packages = [
    pkgs-unstable.androidStudioPackages.canary
  ];

  # Enable and configure the declarative Android SDK
  android-sdk.enable = true;
  android-sdk.packages = sdkPkgs: with sdkPkgs; [
    build-tools-34-0-0
    cmdline-tools-latest
    emulator
    platform-tools
    platforms-android-34
  ];
}
