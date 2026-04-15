# Shared Nushell configuration (cross-platform)
#
# Platform-specific config is in nixos/nushell.nix and darwin/nushell.nix.
# programs.nushell.extraConfig is a `lines` type, so multiple definitions merge.
#
# Integrations:
# - Starship: Prompt (via enableNushellIntegration in starship.nix)
# - Atuin: History search with Ctrl+R (via enableNushellIntegration in atuin.nix)
# - Direnv: Auto-loads .envrc files (via enableNushellIntegration in direnv.nix)
# - Carapace: Tab completions for external commands
# - Navi: Cheatsheet widget with Ctrl+G (manual integration below)
# - Worktrunk: Git worktree management with directory switching (manual integration below)
#              User config with direnv hook is in xdg.configFile (worktrunk.nix)
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

      # Ask GitHub Copilot for a shell command, explain it briefly,
      # and stage the suggested command in the next prompt
      def copilot_shell_prompt [query: string] {
        [
          "You are a shell command assistant."
          "Explain the best command for the user's request briefly."
          "Return exactly this format:"
          "EXPLANATION:"
          "<2-4 short sentences>"
          "COMMAND:"
          "<one shell command only, no markdown, no backticks, empty if unsure>"
          "Prefer a single command the user can run immediately."
          $"User request: ($query)"
        ] | str join "\n\n"
      }

      def copilot_explain_prompt [query: string] {
        [
          "You explain shell commands and CLI usage."
          "Give a short practical explanation in plain text."
          "Mention what the command does, what important flags or arguments mean, and any risk if relevant."
          "Do not suggest a replacement command unless the user explicitly asks for one."
          "Do not use markdown fences or headings."
          $"User request: ($query)"
        ] | str join "\n\n"
      }

      def copilot_run [prompt: string] {
        let result = (
          ^gh copilot -- --model gpt-5.4-mini -p $prompt -s --effort low --allow-all-tools --disable-builtin-mcps --no-custom-instructions --available-tools=
          | complete
        )

        if $result.exit_code != 0 {
          let stderr = ($result.stderr | str trim)
          if ($stderr | is-empty) {
            error make { msg: "gh copilot failed" }
          } else {
            error make { msg: $stderr }
          }
        }

        $result.stdout | str trim
      }

      def copilot_shell_parse [response: string] {
        let parts = ($response | split row "\nCOMMAND:\n")
        let explanation = (
          $parts
          | first
          | default ""
          | str replace -r '^EXPLANATION:\s*' ""
          | str trim
        )
        let raw_command = (
          if ($parts | length) > 1 {
            $parts | skip 1 | str join "\nCOMMAND:\n"
          } else {
            ""
          }
        )
        let command = (
          $raw_command
          | str trim
          | lines
          | first
          | default ""
          | str trim
          | str replace -r '^`(.*)`$' '$1'
        )
        let normalized = ($command | str downcase)

        {
          explanation: $explanation
          command: (
            if $normalized == "" or $normalized == "none" or $normalized == "n/a" or $normalized == "unsure" {
              ""
            } else {
              $command
            }
          )
        }
      }

      def --env ai [...query: string] {
        if ($query | is-empty) {
          print "Usage: ai <question about a shell command>"
          return
        }

        let response = (try {
          copilot_run (copilot_shell_prompt ($query | str join " "))
        } catch {
          print $in.msg
          return
        })
        let parsed = (copilot_shell_parse $response)

        if ($parsed.explanation | is-not-empty) {
          print $parsed.explanation
        }

        if ($parsed.command | is-empty) {
          print ""
          print "No command suggestion returned."
          return
        }

        print ""
        print $"Prepared next command: ($parsed.command)"

        try {
          commandline edit --replace $parsed.command
          commandline set-cursor --end
        } catch {
          print "Could not update the prompt automatically."
        }
      }

      def --env "?" [...query: string] {
        ai ...$query
      }

      def "??" [...query: string] {
        if ($query | is-empty) {
          print "Usage: ?? <command or shell question>"
          return
        }

        try {
          copilot_run (copilot_explain_prompt ($query | str join " ")) | print
        } catch {
          print $in.msg
        }
      }

      # Launch any application detached from terminal (survives shell exit)
      def launch [app: string, ...args: string] {
        let cmd = if ($args | is-empty) { $app } else { $"($app) ($args | str join ' ')" }
        bash -c $"nohup ($cmd) >/dev/null 2>&1 & disown"
        print $"($app) launched"
      }
    '';
  };

  # Carapace for tab completions
  programs.carapace = {
    enable = true;
    enableNushellIntegration = true;
  };
}
