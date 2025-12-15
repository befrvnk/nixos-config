{
  pkgs,
  inputs,
  ...
}:

let
  # Import CSS generation modules
  userChromeCSS = import ./userChrome.nix { inherit pkgs; };
  userContentCSS = import ./userContent.nix { inherit pkgs; };

  # Force the "default" profile to prevent Zen from creating new profiles
  # on each nix store path change (new version = new "installation" to Firefox).
  # Without this, each update would start with an empty profile.
  zenPackage = inputs.zen-browser.packages.${pkgs.system}.beta;
  zenWrapped = zenPackage.overrideAttrs (oldAttrs: {
    nativeBuildInputs = (oldAttrs.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
    postFixup = (oldAttrs.postFixup or "") + ''
      wrapProgram $out/bin/zen \
        --add-flags "-P default"
    '';
  });
in
{
  # Link generated userChrome.css with light/dark media queries
  home.file.".zen/default/chrome/userChrome.css" = {
    source = userChromeCSS;
  };

  # Link generated userContent.css for internal browser pages
  home.file.".zen/default/chrome/userContent.css" = {
    source = userContentCSS;
  };

  programs.zen-browser = {
    enable = true;
    package = zenWrapped;

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

  # Zen Mods (must be installed manually through the browser)
  # These cannot be declaratively configured yet. Install them at: about:zen-mods
  #
  # Better CtrlTab Panel (ID: 72f8f48d-86b9-4487-acea-eb4977b18f21)
  # - Re-style and add customization options for the CtrlTab panel
  #
  # Better Find Bar (ID: a6335949-4465-4b71-926c-4a52d34bc9c0)
  # - Improves the find bar, making it floating with theme match and customization
  #
  # Trackpad Animation (ID: 8039de3b-72e1-41ea-83b3-5077cf0f98d1)
  # - Adds backward and forward animation for trackpad gesture
}
