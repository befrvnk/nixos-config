# ZSH Keybindings Configuration

# Enable emacs keybindings (default for zsh, but explicit is better)
bindkey -e

# Word navigation with Ctrl+Arrow keys
# These bind the sequences that Ghostty sends by default
bindkey "^[[1;5C" forward-word    # Ctrl+Right
bindkey "^[[1;5D" backward-word   # Ctrl+Left

# Also bind Alt+b and Alt+f for word navigation (standard emacs)
# These work with Ghostty's esc:b and esc:f keybinds
bindkey "^[b" backward-word        # Alt+b or ESC+b
bindkey "^[f" forward-word         # Alt+f or ESC+f
bindkey "^[B" backward-word        # Alt+Shift+B
bindkey "^[F" forward-word         # Alt+Shift+F

# Home/End keys
bindkey "^[[H" beginning-of-line   # Home
bindkey "^[[F" end-of-line         # End

# Delete key
bindkey "^[[3~" delete-char        # Delete
