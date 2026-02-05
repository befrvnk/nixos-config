# Darwin-specific Nushell configuration
#
# Uses system defaults for theming - no custom color configuration.
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

_:

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
}
