# Darwin-specific Nushell configuration
#
# On macOS, we use dark theme by default (no automatic switching like Linux).
# Themes are generated from shared/themes.nix without Stylix dependency.
#
# Integrations:
# - Starship: Prompt (via enableNushellIntegration in starship.nix)
# - Atuin: History search with Ctrl+R (via enableNushellIntegration in atuin.nix)
# - Direnv: Auto-loads .envrc files (via enableNushellIntegration in direnv.nix)
# - Carapace: Tab completions for external commands
# - Navi: Cheatsheet widget with Ctrl+G (manual integration below)
# - Worktrunk: Git worktree management with directory switching (manual integration below)
#
# Keybindings:
# - Ctrl+Left/Right: Word navigation
# - Alt+B/F: Word navigation (emacs style)
# - Ctrl+G: Navi cheatsheet widget
# - Ctrl+R: Atuin history search

{ pkgs, ... }:
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

  # Generate nushell color config from base16 palette in NUON format
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
    enable = true;

    extraConfig = ''
      $env.config = {
        show_banner: false

        history: {
          max_size: 10000
          sync_on_enter: true
          file_format: "sqlite"
        }

        completions: {
          case_sensitive: false
          quick: true
          partial: true
          algorithm: "fuzzy"
        }

        keybindings: [
          # Word navigation with Ctrl+Arrow keys
          {
            name: forward_word
            modifier: control
            keycode: right
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movewordright }
          }
          {
            name: backward_word
            modifier: control
            keycode: left
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movewordleft }
          }
          # Alt+B/F for word navigation (emacs style)
          {
            name: forward_word_alt
            modifier: alt
            keycode: char_f
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movewordright }
          }
          {
            name: backward_word_alt
            modifier: alt
            keycode: char_b
            mode: [emacs, vi_normal, vi_insert]
            event: { edit: movewordleft }
          }
        ]
      }

      # Navi widget for Ctrl+G cheatsheet access
      def navi_widget [] {
        let current_input = (commandline)
        let last_command = ($current_input | navi fn widget::last_command | str trim)

        match ($last_command | is-empty) {
          true => {^navi --print | complete | get "stdout"}
          false => {
            let find = $"($last_command)_NAVIEND"
            let replacement = (^navi --print --query $'($last_command)' | complete | get "stdout")

            match ($replacement | str trim | is-empty) {
              false => {$"($current_input)_NAVIEND" | str replace $find $replacement}
              true => $current_input
            }
          }
        }
        | str trim
        | commandline edit --replace $in

        commandline set-cursor --end
      }

      let navi_keybinding = {
        name: "navi"
        modifier: control
        keycode: char_g
        mode: [emacs, vi_normal, vi_insert]
        event: {
          send: executehostcommand
          cmd: "navi_widget"
        }
      }

      $env.config.keybindings = ($env.config.keybindings | append $navi_keybinding)

      # Worktrunk shell integration for directory switching
      def --env --wrapped wt [...args: string] {
        let directive_file = (mktemp)
        try {
          with-env { WORKTRUNK_DIRECTIVE_FILE: $directive_file } {
            ^wt ...$args
          }
          let exit_code = $env.LAST_EXIT_CODE

          if ($directive_file | path exists) {
            let directives = (open $directive_file | str trim)
            if ($directives | is-not-empty) {
              let cd_match = ($directives | parse "cd '{path}'" | get -o path | first)
              let cd_path = if ($cd_match | is-empty) {
                $directives | parse 'cd "{path}"' | get -o path | first
              } else {
                $cd_match
              }
              if ($cd_path | is-not-empty) {
                cd $cd_path
              }
            }
          }
        } catch {
          # Clean up on error
        }
        rm -f $directive_file
      }

      # Launch any application detached from terminal
      def launch [app: string, ...args: string] {
        let cmd = if ($args | is-empty) { $app } else { $"($app) ($args | str join ' ')" }
        bash -c $"nohup ($cmd) >/dev/null 2>&1 & disown"
        print $"($app) launched"
      }

      # Load theme on startup (static dark theme on macOS)
      let theme_file = ($env.HOME | path join ".config/nushell/theme.nuon")
      if ($theme_file | path exists) {
        $env.config.color_config = (open $theme_file)
      }
    '';

    shellAliases = {
      # macOS-specific aliases can go here
    };
  };

  # Carapace for tab completions
  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };

  # Static dark theme for nushell on macOS
  xdg.configFile."nushell/theme.nuon".text = mkNushellTheme darkColors;
}
