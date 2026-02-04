{ pkgs, ... }:

let
  # Script to configure AVDs for AMD hardware GPU support
  configureAvd = pkgs.writeShellScriptBin "configure-avd" ''
    export PATH="${pkgs.gnused}/bin:${pkgs.gnugrep}/bin:${pkgs.findutils}/bin:$PATH"
    ${builtins.readFile ./configure-avd.sh}
  '';
in
{
  home.packages = [
    pkgs.androidStudioPackages.canary
    pkgs.android-studio
    configureAvd
  ];

  # Environment variables for Android emulator GPU compatibility
  # Using systemd.user.sessionVariables so GUI apps (launched via greetd) inherit them
  # home.sessionVariables only works for shell sessions, not graphical sessions
  systemd.user.sessionVariables = {
    # Point Android emulator to system Vulkan ICD for hardware GPU acceleration
    # Without this, emulator fails with VK_ERROR_INCOMPATIBLE_DRIVER
    VK_ICD_FILENAMES = "/run/opengl-driver/share/vulkan/icd.d/radeon_icd.x86_64.json";

    # Fix gray screen issue on AMD Radeon 890M (gfx1150/RDNA 3.5)
    # zerovram initializes GPU memory to zero, working around a gfxstream rendering bug
    RADV_DEBUG = "zerovram";
  };
}
