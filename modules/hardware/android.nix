# Android development support
# - ADB for device communication (emulator + physical devices)
# - KVM for emulator hardware acceleration
# - udev rules handled by systemd's built-in uaccess rules
{ ... }:

{
  # Install ADB and related tools
  programs.adb.enable = true;

  # Create adbusers group (programs.adb doesn't create it automatically)
  users.groups.adbusers = { };

  # Add user to required groups
  users.users.frank.extraGroups = [
    "adbusers" # Android device access via ADB
    "kvm" # Hardware virtualization for Android emulator
  ];
}
