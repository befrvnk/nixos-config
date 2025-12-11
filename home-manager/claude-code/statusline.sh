#!/usr/bin/env bash
# Claude Code statusline script
# Shows: folder (blue), git branch with status (green/yellow), model (magenta), session tokens (colored)

# Colors (ANSI escape codes)
BLUE='\033[34m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
MAGENTA='\033[35m'
RESET='\033[0m'

# Read JSON context from stdin (provided by Claude Code)
input=$(cat)

# Extract model display name from JSON
model=$(@jq@ -r '.model.display_name' <<< "$input")

# Extract context window info (these are cumulative session totals)
input_tokens=$(@jq@ -r '.context_window.total_input_tokens // 0' <<< "$input")
context_size=$(@jq@ -r '.context_window.context_window_size // 200000' <<< "$input")

# Format token count (in k)
input_k=$((input_tokens / 1000))
context_k=$((context_size / 1000))

# Color based on session input vs context window
# Green: under context window, Yellow: 1-2x, Red: over 2x
if [ "$input_tokens" -lt "$context_size" ]; then
  context_color="$GREEN"
elif [ "$input_tokens" -lt $((context_size * 2)) ]; then
  context_color="$YELLOW"
else
  context_color="$RED"
fi

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

echo -e "${BLUE}$folder${RESET}$git_part ${MAGENTA}$model${RESET} ${context_color}${input_k}k/${context_k}k${RESET}"
