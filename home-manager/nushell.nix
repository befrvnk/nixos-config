# Nushell configuration with Carapace completions
#
# Nushell is a modern shell with structured data pipelines.
# Carapace provides completions for 1000+ commands.
#
# Integrations:
# - Starship: Prompt (via enableNushellIntegration in starship.nix)
# - Atuin: History search with Ctrl+R (via enableNushellIntegration in atuin.nix)
# - Direnv: Auto-loads .envrc files (via enableNushellIntegration in direnv.nix)
# - Carapace: Tab completions for external commands
# - Navi: Cheatsheet widget with Ctrl+G (manual integration below)
#
# Keybindings:
# - Ctrl+Left/Right: Word navigation
# - Alt+B/F: Word navigation (emacs style)
# - Ctrl+G: Navi cheatsheet widget
# - Ctrl+R: Atuin history search

{ ... }:

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
}
