# NixOS-specific Nushell configuration
#
# Shared config (keybindings, navi, wt, launch, carapace) is in shared/nushell.nix.
# This file handles Stylix theme integration and NixOS-specific aliases.
#
# Theme switching:
# - Light and dark theme files are generated at build time using Stylix colors (NUON format)
# - Darkman copies the active theme to ~/.local/state/nushell/theme.nuon
# - A pre_prompt hook loads the theme file for automatic color updates

{ pkgs, lib, ... }:
let
  themes = import ../../shared/themes.nix { inherit pkgs; };

  # Parse base16 scheme YAML to get color values
  parseBase16Scheme =
    schemeFile:
    let
      jsonFile = pkgs.runCommand "base16-to-json" { } ''
        ${pkgs.yq-go}/bin/yq -o json ${schemeFile} > $out
      '';
    in
    builtins.fromJSON (builtins.readFile jsonFile);

  darkColors = parseBase16Scheme themes.dark.base16Scheme;
  lightColors = parseBase16Scheme themes.light.base16Scheme;

  # Generate nushell color config from base16 palette in NUON format
  # Based on Stylix's nushell module (https://github.com/nix-community/stylix/blob/master/modules/nushell/hm.nix)
  # NUON format allows runtime loading (source requires constant path at parse time)
  mkNushellTheme =
    colors:
    let
      p = colors.palette;
    in
    ''
      {
        separator: "${p.base03}"
        leading_trailing_space_bg: "${p.base04}"
        header: "${p.base0B}"
        date: "${p.base0E}"
        filesize: "${p.base0D}"
        row_index: "${p.base0C}"
        bool: "${p.base08}"
        int: "${p.base0B}"
        duration: "${p.base08}"
        range: "${p.base08}"
        float: "${p.base08}"
        string: "${p.base04}"
        nothing: "${p.base08}"
        binary: "${p.base08}"
        cellpath: "${p.base08}"
        hints: dark_gray
        shape_garbage: {fg: "${p.base07}", bg: "${p.base08}"}
        shape_bool: "${p.base0D}"
        shape_int: {fg: "${p.base0E}", attr: b}
        shape_float: {fg: "${p.base0E}", attr: b}
        shape_range: {fg: "${p.base0A}", attr: b}
        shape_internalcall: {fg: "${p.base0C}", attr: b}
        shape_external: "${p.base0C}"
        shape_externalarg: {fg: "${p.base0B}", attr: b}
        shape_literal: "${p.base0D}"
        shape_operator: "${p.base0A}"
        shape_signature: {fg: "${p.base0B}", attr: b}
        shape_string: "${p.base0B}"
        shape_filepath: "${p.base0D}"
        shape_globpattern: {fg: "${p.base0D}", attr: b}
        shape_variable: "${p.base0E}"
        shape_flag: {fg: "${p.base0D}", attr: b}
        shape_custom: {attr: b}
      }
    '';
in

{
  programs.nushell = {
    extraConfig = ''
      # Helper function to load theme from NUON file
      def load-nushell-theme [] {
        let theme_file = ($env.HOME | path join ".local/state/nushell/theme.nuon")
        if ($theme_file | path exists) {
          open $theme_file
        } else {
          # Fallback: try to load from config directory
          let dark_theme = ($env.HOME | path join ".config/nushell/theme-dark.nuon")
          if ($dark_theme | path exists) {
            open $dark_theme
          } else {
            null
          }
        }
      }

      # Load theme on startup
      let theme = (load-nushell-theme)
      if $theme != null {
        $env.config.color_config = $theme
      }

      # Pre-prompt hook to reload theme when it changes
      # This enables automatic theme switching when darkman updates the theme file
      $env.config.hooks.pre_prompt = ($env.config.hooks.pre_prompt | default [] | append {||
        let theme_file = ($env.HOME | path join ".local/state/nushell/theme.nuon")
        if ($theme_file | path exists) {
          # Only reload if file has changed since last check
          let current_mtime = (ls -l $theme_file | get 0.modified)
          let last_mtime = ($env.NUSHELL_THEME_MTIME? | default "")
          if $current_mtime != $last_mtime {
            $env.config.color_config = (open $theme_file)
            $env.NUSHELL_THEME_MTIME = $current_mtime
          }
        }
      })
    '';

    # Environment setup: ensure theme state directory exists and initialize theme
    extraEnv = ''
      # Create theme state directory if it doesn't exist
      mkdir ($env.HOME | path join ".local/state/nushell")

      # If no theme is set yet, copy the dark theme as default
      let theme_file = ($env.HOME | path join ".local/state/nushell/theme.nuon")
      if not ($theme_file | path exists) {
        let dark_theme = ($env.HOME | path join ".config/nushell/theme-dark.nuon")
        if ($dark_theme | path exists) {
          cp $dark_theme $theme_file
        }
      }
    '';

    shellAliases = {
      # Firewall log viewing (migrated from zsh)
      firewall-log = "journalctl -k | grep 'refused'";
      firewall-log-live = "sudo dmesg --follow | grep 'refused'";
    };
  };

  # Generate theme files for both light and dark modes in NUON format
  # These are copied to ~/.local/state/nushell/theme.nuon by darkman
  xdg.configFile."nushell/theme-dark.nuon".text = mkNushellTheme darkColors;
  xdg.configFile."nushell/theme-light.nuon".text = mkNushellTheme lightColors;

  # Disable Stylix's nushell target since we manage themes ourselves
  stylix.targets.nushell.enable = lib.mkForce false;
}
