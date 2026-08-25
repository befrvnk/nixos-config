{ config, pkgs, ... }:

let
  syncTheme = pkgs.writeShellScript "cliamp-theme-sync" ''
    if /usr/bin/defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
      theme=dark
    else
      theme=light
    fi

    ${pkgs.cliamp}/bin/cliamp theme "cliamp-$theme" >/dev/null 2>&1 || true
  '';
in
{
  launchd.agents.cliamp-theme-sync = {
    enable = true;
    config = {
      ProgramArguments = [ "${syncTheme}" ];
      RunAtLoad = true;
      WatchPaths = [ "${config.home.homeDirectory}/Library/Preferences/.GlobalPreferences.plist" ];
    };
  };
}
