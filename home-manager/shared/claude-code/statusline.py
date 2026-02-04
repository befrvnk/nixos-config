"""
Claude Code statusline script with accurate context tracking.

Uses pre-calculated used_percentage from Claude Code for accuracy.
"""

import json
import os
import subprocess
import sys

# ANSI colors
BLUE = '\033[34m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
RED = '\033[31m'
MAGENTA = '\033[35m'
RESET = '\033[0m'


def get_git_info(git_path: str) -> str:
    """Get git branch and dirty status."""
    try:
        branch = subprocess.run(
            [git_path, 'branch', '--show-current'],
            capture_output=True, text=True, timeout=1
        ).stdout.strip()

        if not branch:
            return ""

        status = subprocess.run(
            [git_path, 'status', '--porcelain'],
            capture_output=True, text=True, timeout=1
        ).stdout.strip()

        if status:
            return f" {YELLOW}{branch}*{RESET}"
        return f" {GREEN}{branch}{RESET}"
    except Exception:
        return ""


def get_context_from_json(data: dict) -> tuple[int, int, int | None]:
    """
    Get context info from JSON data passed by Claude Code.

    Returns (current_tokens, context_size, used_percentage).
    used_percentage is the pre-calculated value from Claude Code if available.
    """
    context_window = data.get('context_window', {})
    context_size = context_window.get('context_window_size', 200000)

    # Prefer pre-calculated percentage from Claude Code (most accurate)
    used_percentage = context_window.get('used_percentage')
    if used_percentage is not None:
        # Calculate tokens from percentage for display
        current_tokens = int((used_percentage / 100) * context_size)
        return (current_tokens, context_size, used_percentage)

    # Fall back to calculating from current_usage
    current_usage = context_window.get('current_usage')
    if current_usage:
        input_tokens = current_usage.get('input_tokens', 0)
        cache_creation = current_usage.get('cache_creation_input_tokens', 0)
        cache_read = current_usage.get('cache_read_input_tokens', 0)
        output_tokens = current_usage.get('output_tokens', 0)
        # All token types contribute to context
        current_tokens = input_tokens + cache_creation + cache_read + output_tokens
        return (current_tokens, context_size, None)

    # Fall back to total_input_tokens (cumulative, less accurate)
    total_input = context_window.get('total_input_tokens', 0)
    return (total_input, context_size, None)


def format_tokens(tokens: int) -> str:
    """Format token count with k suffix."""
    if tokens >= 1000:
        return f"{tokens // 1000}k"
    return str(tokens)


def get_color_for_percent(percent: int) -> str:
    """Get color based on context usage percentage."""
    if percent < 50:
        return GREEN
    elif percent < 75:
        return YELLOW
    elif percent < 90:
        return RED
    else:
        return "\033[1;31m"  # Bold red for critical


def main():
    # Read JSON from stdin
    try:
        input_data = json.load(sys.stdin)
    except json.JSONDecodeError:
        print(f"{RED}[error]{RESET}")
        return

    # Get model name
    model = input_data.get('model', {}).get('display_name', 'unknown')

    # Get context info from JSON (authoritative source from Claude Code)
    current_tokens, context_size, used_percentage = get_context_from_json(input_data)

    # Use pre-calculated percentage if available, otherwise calculate
    if used_percentage is not None:
        percent = int(used_percentage)
    else:
        percent = int((current_tokens / context_size) * 100) if context_size > 0 else 0

    # Get color for percentage
    percent_color = get_color_for_percent(percent)

    # Get folder name
    folder = os.path.basename(os.getcwd())

    # Get git info (using git path from environment or default)
    git_path = os.environ.get('GIT_PATH', 'git')
    git_info = get_git_info(git_path)

    # Format output
    # folder (blue) | git branch | model (magenta) | tokens/max (colored) | percent (colored)
    tokens_str = f"{format_tokens(current_tokens)}/{format_tokens(context_size)}"

    print(f"{BLUE}{folder}{RESET}{git_info} {MAGENTA}{model}{RESET} {percent_color}{tokens_str} ({percent}%){RESET}")


if __name__ == '__main__':
    main()
