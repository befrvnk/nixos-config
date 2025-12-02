{ pkgs, ... }:
{
  # Install the governor switching scripts
  home.packages = [
    (pkgs.writeShellScriptBin "switch-governor" (builtins.readFile ./switch-governor.sh))
    (pkgs.writeShellScriptBin "set-governor-helper" (builtins.readFile ./set-governor-helper.sh))
    pkgs.libnotify # For notify-send command
  ];
}
