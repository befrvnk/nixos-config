{ pkgs, ... }:

let
  # Script that returns success (0) if lid is closed, failure (1) if open
  # Used by PAM to skip fingerprint auth when lid is closed
  checkLidClosed = pkgs.writeShellScript "check-lid-closed" ''
    [ -f /run/fprintd-lid-closed ]
  '';
in
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

  # Prevent fprintd from starting when lid is closed
  # The lid-manager service creates this flag file when lid closes
  # This blocks D-Bus activation of fprintd, so sudo goes straight to password
  systemd.services.fprintd.unitConfig = {
    ConditionPathExists = "!/run/fprintd-lid-closed";
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

        # Skip fingerprint auth if lid is closed (success=1 skips next module)
        auth [success=1 default=ignore] pam_exec.so quiet ${checkLidClosed}
        auth sufficient pam_fprintd.so timeout=10 max-tries=3
        auth include login
      '';
    };

    # Enable fingerprint for polkit (used by 1Password and other GUI apps)
    polkit-1 = {
      rules.auth = {
        # Skip fingerprint if lid is closed (success=1 skips next module)
        fprintd-lid-check = {
          order = 11390;
          control = "[success=1 default=ignore]";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "${checkLidClosed}"
          ];
        };
        fprintd = {
          order = 11400;
          control = "sufficient";
          modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
          args = [
            "timeout=10"
            "max-tries=3"
          ];
        };
      };
    };

    # Enable fingerprint for sudo with timeout
    sudo = {
      rules.auth = {
        fprintd-lid-check = {
          order = 11390;
          control = "[success=1 default=ignore]";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "${checkLidClosed}"
          ];
        };
        fprintd = {
          order = 11400;
          control = "sufficient";
          modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
          args = [
            "timeout=10"
            "max-tries=3"
          ];
        };
      };
    };

    # Enable fingerprint for login with timeout
    login = {
      rules.auth = {
        fprintd-lid-check = {
          order = 11390;
          control = "[success=1 default=ignore]";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "${checkLidClosed}"
          ];
        };
        fprintd = {
          order = 11400;
          control = "sufficient";
          modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
          args = [
            "timeout=10"
            "max-tries=3"
          ];
        };
      };
    };

    # Enable fingerprint for greetd with a shorter timeout
    greetd = {
      rules.auth = {
        fprintd-lid-check = {
          order = 11390;
          control = "[success=1 default=ignore]";
          modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
          args = [
            "quiet"
            "${checkLidClosed}"
          ];
        };
        fprintd = {
          order = 11400;
          control = "sufficient";
          modulePath = "${pkgs.fprintd}/lib/security/pam_fprintd.so";
          args = [
            "timeout=5"
            "max-tries=2"
          ];
        };
      };
    };
  };
}
