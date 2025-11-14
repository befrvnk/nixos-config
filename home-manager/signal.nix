{ pkgs, ... }:

# Signal Desktop wrapper with GNOME keyring support
#
# This configuration wraps signal-desktop to use the gnome-libsecret password store.
# This is necessary because Signal stores its database encryption key in the OS keyring,
# and the keyring backend is tied to the desktop environment.
#
# Issue:
# When switching from GNOME to a different desktop environment (like Niri), Signal
# attempts to use a different keyring backend (e.g., basic_text instead of gnome_libsecret).
# Since the encryption key was stored in the GNOME keyring, Signal cannot access it
# and fails to open the database.
#
# Solution:
# By passing the --password-store=gnome-libsecret flag, we force Signal to always use
# the GNOME keyring backend, regardless of the current desktop environment. This allows
# Signal to access the encryption key even when running under Niri or other non-GNOME
# environments.
#
# Security benefit:
# Using gnome-libsecret keeps the database encryption key stored securely in the GNOME
# keyring, which is itself encrypted and protected. Without this flag, Signal would fall
# back to the basic_text backend, which stores the encryption key in an unencrypted plain
# text file on disk - a significant security downgrade. This wrapper maintains the security
# of your Signal database even when using non-GNOME desktop environments.
#
# Note:
# This requires gnome-keyring to be running in your session. Make sure it's configured
# to start with your desktop environment.

let
  signal-desktop-wrapped = pkgs.symlinkJoin {
    name = "signal-desktop";
    paths = [ pkgs.signal-desktop ];
    buildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/signal-desktop \
        --add-flags "--password-store=gnome-libsecret"
    '';
  };
in
{
  home.packages = [ signal-desktop-wrapped ];
}
