{
  inputs,
  pkgs,
  ...
}:
let
  system = pkgs.stdenv.hostPlatform.system;

  windowManagement = inputs.vicinae.lib.${system}.mkVicinaeExtension {
    pname = "vicinae-extension-window-management";
    version = "0";
    src = ./vicinae/extensions/window-management;
  };
in
{
  # Install the Darwin-capable Vicinae package from the upstream flake.
  home.packages = [ inputs.vicinae.packages.${system}.default ];

  # Vicinae uses standard Unix data directories on macOS, so Home Manager's
  # xdg.dataFile maps to ~/.local/share/vicinae/extensions/...
  # Use the manifest/provider id as the directory name so deeplinks stay stable.
  xdg.dataFile."vicinae/extensions/window-management".source = windowManagement;
}
