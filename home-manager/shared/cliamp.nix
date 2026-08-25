{ pkgs, ... }:

let
  themes = import ../../shared/themes.nix { inherit pkgs; };

  mkCliampTheme = colors: ''
    bg = "${colors.base00}"
    accent = "${colors.base0D}"
    bright_fg = "${colors.base05}"
    fg = "${colors.base04}"
    green = "${colors.base0B}"
    yellow = "${colors.base0A}"
    red = "${colors.base08}"
  '';

  selectTheme =
    if pkgs.stdenv.hostPlatform.isDarwin then
      ''
        if /usr/bin/defaults read -g AppleInterfaceStyle >/dev/null 2>&1; then
          theme=cliamp-dark
        else
          theme=cliamp-light
        fi
      ''
    else
      ''
        if [ "$(${pkgs.coreutils}/bin/cat "$HOME/.local/state/cliamp/theme" 2>/dev/null)" = "light" ]; then
          theme=cliamp-light
        else
          theme=cliamp-dark
        fi
      '';

  cliamp = pkgs.writeShellScriptBin "cliamp" ''
    ${selectTheme}

    exec ${pkgs.cliamp}/bin/cliamp --start-theme "$theme" "$@"
  '';
in
{
  home = {
    file = {
      ".config/cliamp/themes/cliamp-dark.toml".text = mkCliampTheme themes.dark.palette;
      ".config/cliamp/themes/cliamp-light.toml".text = mkCliampTheme themes.light.palette;
    };

    packages = [ cliamp ];
  };
}
