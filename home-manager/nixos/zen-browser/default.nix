{
  pkgs,
  inputs,
  ...
}:

let
  # Import CSS generation modules
  userChromeCSS = import ./userChrome.nix { inherit pkgs; };
  userContentCSS = import ./userContent.nix { inherit pkgs; };

  zenPackage = inputs.zen-browser.packages.${pkgs.system}.beta;

  # Create a launcher script that forces the correct profile
  # This prevents Zen from using wrong profiles when the nix store path changes
  zenLauncher = pkgs.writeShellScriptBin "zen-launch" ''
    exec ${zenPackage}/bin/zen -P "Default Profile" "$@"
  '';
in
{
  # Add our launcher script to PATH
  home.packages = [ zenLauncher ];

  # Link generated userChrome.css with light/dark media queries
  home.file.".zen/default/chrome/userChrome.css" = {
    source = userChromeCSS;
  };

  # Link generated userContent.css for internal browser pages
  home.file.".zen/default/chrome/userContent.css" = {
    source = userContentCSS;
  };

  # Single desktop entry using our profile-aware launcher
  xdg.desktopEntries.zen-browser = {
    name = "Zen Browser";
    genericName = "Web Browser";
    exec = "zen-launch %U";
    icon = "zen-browser";
    terminal = false;
    categories = [
      "Network"
      "WebBrowser"
    ];
    mimeType = [
      "text/html"
      "text/xml"
      "application/xhtml+xml"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
    ];
    startupNotify = true;
    settings = {
      StartupWMClass = "zen-beta";
    };
    actions = {
      new-window = {
        name = "New Window";
        exec = "zen-launch --new-window %U";
      };
      new-private-window = {
        name = "New Private Window";
        exec = "zen-launch --private-window %U";
      };
    };
  };

  # Hide the original desktop entry from the package
  xdg.desktopEntries.zen-beta = {
    name = "Zen Browser (Beta)";
    exec = "zen %U";
    icon = "zen-browser";
    terminal = false;
    settings = {
      NoDisplay = "true";
    };
  };

  programs.zen-browser = {
    enable = true;
    package = zenPackage;

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
