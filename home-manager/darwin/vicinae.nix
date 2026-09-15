{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  agenda = inputs.vicinae-extensions.packages.${system}.agenda;

  brightness = inputs.vicinae.lib.${system}.mkVicinaeExtension {
    pname = "vicinae-extension-brightness";
    version = "0";
    src = ./vicinae/extensions/brightness;
  };

  geminiTextTools = inputs.vicinae.lib.${system}.mkVicinaeExtension {
    pname = "vicinae-extension-gemini-text-tools";
    version = "0";
    src = ../nixos/vicinae/extensions/gemini-text-tools;
  };

  windowManagement = inputs.vicinae.lib.${system}.mkVicinaeExtension {
    pname = "vicinae-extension-window-management";
    version = "0";
    src = ./vicinae/extensions/window-management;
  };
in
{
  # The official app is installed with Homebrew so its stable signature and
  # bundle path retain macOS Accessibility permissions across upgrades.
  xdg.dataFile = {
    "vicinae/extensions/agenda".source = agenda;
    "vicinae/extensions/brightness".source = brightness;
    "vicinae/extensions/gemini-text-tools".source = geminiTextTools;
    "vicinae/extensions/window-management".source = windowManagement;
  };
}
