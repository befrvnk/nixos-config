{ config, pkgs, ... }:

{
  # Enable fingerprint reader support
  services.fprintd = {
    enable = true;
    # Framework laptops now work with regular fprintd (1.94.5) which has Ctrl+C support
    # No need for TOD drivers anymore on modern Framework hardware
    # If fingerprint stops working after rebuild, uncomment these lines:
    # tod.enable = true;
    # tod.driver = pkgs.libfprint-2-tod1-goodix;
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

  # Configure PAM to enable fingerprint authentication with proper timeout
  security.pam.services = {
    # Enable fingerprint for swaylock
    # This allows unlocking the screen with fingerprint
    swaylock = {
      text = ''
        # Account management
        account required pam_unix.so

        # Authentication with fingerprint (try first, then fall back to password)
        auth sufficient pam_fprintd.so timeout=10 max-tries=3
        auth include login
      '';
    };

    # Enable fingerprint for polkit (used by 1Password and other GUI apps)
    # Using the built-in fprintAuth with custom module path to pass timeout args
    polkit-1 = {
      rules.auth.fprintd = {
        order = 11400; # Before unix auth
        control = "sufficient";
        modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
        args = [
          "timeout=10"
          "max-tries=3"
        ];
      };
    };

    # Enable fingerprint for sudo with timeout
    sudo = {
      rules.auth.fprintd = {
        order = 11400; # Before unix auth
        control = "sufficient";
        modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
        args = [
          "timeout=10"
          "max-tries=3"
        ];
      };
    };

    # Enable fingerprint for login with timeout
    login = {
      rules.auth.fprintd = {
        order = 11400; # Before unix auth
        control = "sufficient";
        modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
        args = [
          "timeout=10"
          "max-tries=3"
        ];
      };
    };
  };
}
