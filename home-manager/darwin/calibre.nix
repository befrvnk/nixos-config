# Calibre with ACSM fulfillment and Adobe DRM support.

{
  config,
  lib,
  pkgs,
  ...
}:

let
  deACSM = pkgs.fetchurl {
    url = "https://github.com/Leseratte10/acsm-calibre-plugin/releases/download/v0.0.16/DeACSM_0.0.16.zip";
    hash = "sha256-tfYbonufW86lfB+yPTbLwb2JEKHzOvCTdbvuNlGHC1A=";
  };

  deDRMTools = pkgs.fetchzip {
    url = "https://github.com/noDRM/DeDRM_tools/releases/download/v10.0.9/DeDRM_tools_10.0.9.zip";
    hash = "sha256-3gMzURkI6U7tU3CDiK4Y81xGH0YxrMIVt2dt3JRpih4=";
    stripRoot = false;
  };

  installCalibrePlugins = pkgs.writeShellScript "install-calibre-plugins" ''
    set -eu

    calibre_customize="/Applications/calibre.app/Contents/MacOS/calibre-customize"
    calibre_config="${config.home.homeDirectory}/Library/Preferences/calibre"

    if [ ! -x "$calibre_customize" ]; then
      echo "Calibre is not installed yet; plugins will be installed on the next activation."
      exit 0
    fi

    /bin/mkdir -p "$calibre_config/plugins"
    export CALIBRE_CONFIG_DIRECTORY="$calibre_config"

    install_plugin() {
      source_path="$1"
      plugin_name="$2"
      installed_path="$calibre_config/plugins/$plugin_name.zip"

      if [ ! -f "$installed_path" ] || ! /usr/bin/cmp -s "$source_path" "$installed_path"; then
        "$calibre_customize" --add-plugin "$source_path"
      fi
    }

    install_plugin "${deACSM}" "DeACSM"
    install_plugin "${deDRMTools}/DeDRM_plugin.zip" "DeDRM"
  '';
in
{
  home.activation.installCalibrePlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${installCalibrePlugins}
  '';
}
