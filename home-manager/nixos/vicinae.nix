{
  pkgs,
  inputs,
  ...
}:
let
  localGeminiTextTools = inputs.vicinae.lib.${pkgs.stdenv.hostPlatform.system}.mkVicinaeExtension {
    pname = "vicinae-extension-gemini-text-tools";
    version = "0";
    src = ./vicinae/extensions/gemini-text-tools;
  };
in
{
  programs.vicinae = {
    enable = true;

    # Use the module's systemd integration
    systemd.enable = true;

    settings = {
      launcher_window = {
        opacity = 1.0;
        client_side_decorations = {
          enabled = true;
        };
        layer_shell = {
          enabled = false; # Disabled for niri compatibility
        };
      };
    };

    extensions = with inputs.vicinae-extensions.packages.${pkgs.stdenv.hostPlatform.system}; [
      # bluetooth # TODO: re-enable once usocket builds with Node.js 24
      localGeminiTextTools
      nix
      wifi-commander
    ];
  };

  # Avoid Stylix's built-in Vicinae target until it stops writing renamed
  # services.vicinae aliases; Noctalia's reviewed template owns runtime colors.
  stylix.targets.vicinae.enable = false;
}
