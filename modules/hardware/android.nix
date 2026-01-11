# Android development support
# - KVM for emulator hardware acceleration
# - udev rules handled by systemd's built-in uaccess rules (systemd 258+)
# - ADB installed via android-tools package in system packages
{ ... }:

{
  # Add user to kvm group for emulator hardware acceleration
  users.users.frank.extraGroups = [
    "kvm" # Hardware virtualization for Android emulator
  ];
}
