{ pkgs, ... }:

{
  # Enable fingerprint reader support
  services.fprintd = {
    enable = true;
    # Use the TOD (Touch OEM Drivers) variant for better compatibility with Framework laptops
    tod.enable = true;
    tod.driver = pkgs.libfprint-2-tod1-goodix;
  };

  # Add polkit rules to allow fingerprint enrollment and verification
  security.polkit.extraConfig = ''
    polkit.addRule(function (action, subject) {
      if (action.id == "net.reactivated.fprint.device.enroll" ||
          action.id == "net.reactivated.fprint.device.verify") {
        return polkit.Result.YES;
      }
    });
  '';

  # Configure PAM to enable fingerprint authentication
  security.pam.services = {
    # Enable fingerprint for swaylock
    # This allows unlocking the screen with fingerprint
    swaylock = {
      text = ''
        # Account management
        account required pam_unix.so

        # Authentication with fingerprint (try first, then fall back to password)
        auth sufficient pam_fprintd.so
        auth include login
      '';
    };

    # Enable fingerprint for polkit (used by 1Password and other GUI apps)
    # This allows authenticating 1Password with fingerprint
    polkit-1.fprintAuth = true;

    # Enable fingerprint for sudo (optional but convenient)
    sudo.fprintAuth = true;

    # Enable fingerprint for login (optional)
    login.fprintAuth = true;
  };
}
