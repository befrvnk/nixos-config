# Nushell configuration with Carapace completions
#
# Nushell is a modern shell with structured data pipelines.
# Carapace provides completions for 1000+ commands.
#
# Theme switching:
# - Light and dark theme files are generated at build time using Stylix colors (NUON format)
# - Darkman copies the active theme to ~/.local/state/nushell/theme.nuon
# - A pre_prompt hook loads the theme file for automatic color updates
#
# Integrations:
# - Starship: Prompt (via enableNushellIntegration in starship.nix)
# - Atuin: History search with Ctrl+R (via enableNushellIntegration in atuin.nix)
# - Direnv: Auto-loads .envrc files (via enableNushellIntegration in direnv.nix)
# - Carapace: Tab completions for external commands
# - Navi: Cheatsheet widget with Ctrl+G (manual integration below)
# - Worktrunk: Git worktree management with directory switching (manual integration below)
#              User config with direnv hook is in xdg.configFile below
#
# Keybindings:
# - Ctrl+Left/Right: Word navigation
# - Alt+B/F: Word navigation (emacs style)
# - Ctrl+G: Navi cheatsheet widget
# - Ctrl+R: Atuin history search

{ pkgs, lib, ... }:
let
  themes = import ./themes.nix { inherit pkgs; };

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
  # Based on Stylix's nushell module but with string using base05 for better readability
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
        string: "${p.base05}"
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
      # (home-manager navi module doesn't have enableNushellIntegration)
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
      # Wraps the wt binary to enable `wt switch` to change the shell's directory
      def --env --wrapped wt [...args: string] {
        let directive_file = (mktemp)
        try {
          with-env { WORKTRUNK_DIRECTIVE_FILE: $directive_file } {
            ^wt ...$args
          }
          let exit_code = $env.LAST_EXIT_CODE

          # Parse and execute directives (cd commands)
          if ($directive_file | path exists) {
            let directives = (open $directive_file | str trim)
            if ($directives | is-not-empty) {
              # Extract path from cd command: cd '/path/to/dir' or cd "/path/to/dir"
              let cd_match = ($directives | parse "cd '{path}'" | get -o path | first)
              let cd_path = if ($cd_match | is-empty) {
                # Try double quotes
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

  # Carapace for tab completions
  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };

  # Generate theme files for both light and dark modes in NUON format
  # These are copied to ~/.local/state/nushell/theme.nuon by darkman
  xdg.configFile."nushell/theme-dark.nuon".text = mkNushellTheme darkColors;
  xdg.configFile."nushell/theme-light.nuon".text = mkNushellTheme lightColors;

  # Worktrunk user config with direnv auto-allow hook
  # User hooks run automatically without approval on all repositories
  xdg.configFile."worktrunk/config.toml".text = ''
    # Auto-allow direnv in new worktrees
    post-create = "direnv allow"
  '';

  # Disable Stylix's nushell target since we manage themes ourselves
  stylix.targets.nushell.enable = lib.mkForce false;
}
