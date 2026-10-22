{ pkgs, ... }:
{
  # Native Noctalia verifies fingerprints over fprintd D-Bus. Keep its password
  # stack independent of login/TTY fingerprint and lid-check rules. No nullok,
  # permissive modules or changes to other authentication services.
  security.pam.services.noctalia.text = ''
    auth required ${pkgs.pam}/lib/security/pam_unix.so
    account required ${pkgs.pam}/lib/security/pam_unix.so
  '';
}
