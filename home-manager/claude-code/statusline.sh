#!/usr/bin/env bash
# Claude Code statusline script
# Shows: folder (blue), git branch with status (green/yellow), model (magenta)

# Colors (ANSI escape codes)
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
MAGENTA='\033[35m'
RESET='\033[0m'

# Read JSON context from stdin (provided by Claude Code)
input=$(cat)

# Extract model display name from JSON
model=$(@jq@ -r '.model.display_name' <<< "$input")

# Folder (basename of current directory)
folder=$(basename "$PWD")

# Git branch and status (if in a git repo)
branch=$(@git@ branch --show-current 2>/dev/null)
if [ -n "$branch" ]; then
  # Check git status
  status=$(@git@ status --porcelain 2>/dev/null)
  if [ -n "$status" ]; then
    # Dirty - show in yellow with indicator
    git_part=" ${YELLOW}$branch*${RESET}"
  else
    # Clean - show in green
    git_part=" ${GREEN}$branch${RESET}"
  fi
else
  git_part=""
fi

echo -e "${BLUE}$folder${RESET}$git_part ${MAGENTA}$model${RESET}"
