{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
let
  themeFile = "${config.xdg.stateHome}/noctalia/vscode/NoctaliaTheme-color-theme.json";
  vsix = pkgs.fetchurl {
    name = "noctaliatheme-0.0.5.vsix";
    url = "https://noctalia.gallery.vsassets.io/_apis/public/gallery/publisher/noctalia/extension/noctaliatheme/0.0.5/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage";
    hash = "sha256-aTSk3yYkBw5GrD0CbRL2wo3SlBffzBTDe1pZoZa1URQ=";
  };
  extension =
    (pkgs.vscode-utils.buildVscodeMarketplaceExtension {
      inherit vsix;
      mktplcRef = {
        publisher = "noctalia";
        name = "noctaliatheme";
        version = "0.0.5";
      };
    }).overrideAttrs
      (old: {
        # Keep the official manifest/icon immutable; only palette data is external.
        postInstall = (old.postInstall or "") + ''
          theme="$out/share/vscode/extensions/noctalia.noctaliatheme/themes/NoctaliaTheme-color-theme.json"
          rm "$theme"
          ln -s ${lib.escapeShellArg themeFile} "$theme"
        '';
      });
  # Reuse the already-declared font settings from our pinned Stylix version,
  # without its fixed theme selector or generated color extension.
  fonts =
    builtins.removeAttrs
      (import "${inputs.stylix}/modules/vscode/templates/settings.nix" config.stylix.fonts)
      [ "workbench.colorTheme" ];
  placeholder = builtins.toJSON {
    name = "NoctaliaTheme";
    type = "dark";
    colors = { };
    tokenColors = [ ];
  };
in
{
  stylix.targets.vscode.enable = false;
  programs.vscode = {
    enable = true;
    # Keep other extensions manually installable; the theme remains Nix-owned.
    mutableExtensionsDir = true;
    profiles.default = {
      extensions = [ extension ];
      enableUpdateCheck = false;
      enableExtensionUpdateCheck = false;
      userSettings = fonts // {
        "workbench.colorTheme" = "NoctaliaTheme";
        "extensions.autoUpdate" = false;
        # The upstream extension has one vs-dark contribution. Noctalia writes
        # the active palette; don't let VS Code select a competing light theme.
        "window.autoDetectColorScheme" = false;
      };
    };
  };

  programs.noctalia.settings.theme.templates.user.vscode = {
    input_path = "${inputs.noctalia-community-templates}/vscode/vscode.json";
    output_path = "$XDG_STATE_HOME/noctalia/vscode/NoctaliaTheme-color-theme.json";
  };

  home.activation.prepareVscodeNoctaliaTheme =
    lib.hm.dag.entryBetween [ "linkGeneration" ] [ "writeBoundary" ]
      ''
        $DRY_RUN_CMD ${pkgs.python3}/bin/python3 ${./prepare_theme_output.py} \
          ${lib.escapeShellArg themeFile} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/noctalia/vscode.pre-template.json"} \
          --placeholder ${lib.escapeShellArg placeholder}
      '';
}
