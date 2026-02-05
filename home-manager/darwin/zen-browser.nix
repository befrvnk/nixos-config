_:

{
  programs.zen-browser = {
    enable = true;

    # Declarative extension management using policies
    # Extensions are auto-installed and force-enabled
    policies =
      let
        mkExtensionSettings = builtins.mapAttrs (
          guid: slug: {
            install_url = "https://addons.mozilla.org/firefox/downloads/latest/${slug}/latest.xpi";
            installation_mode = "force_installed";
          }
        );
      in
      {
        # Extension configuration
        ExtensionSettings = mkExtensionSettings {
          "uBlock0@raymondhill.net" = "ublock-origin";
          # Note: 1Password extension integration requires 1Password desktop app
          "{d634138d-c276-4fc8-924b-40a0ea21d284}" = "1password-x-password-manager";
        };

        # Browser behavior policies
        DisableAppUpdate = true; # Updates managed by Nix
        DisableTelemetry = true;
        DisablePocket = true;
        DontCheckDefaultBrowser = true;
        NoDefaultBookmarks = true;
        OfferToSaveLogins = false; # Using 1Password instead
        PasswordManagerEnabled = false; # Using 1Password instead

        # Privacy settings
        EnableTrackingProtection = {
          Value = true;
          Locked = true;
          Cryptomining = true;
          Fingerprinting = true;
        };
      };
  };
}
