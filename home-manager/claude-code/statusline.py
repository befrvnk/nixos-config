"""
Claude Code statusline script with accurate context tracking.

Parses the transcript JSONL file to calculate actual context usage,
properly handling /compact boundaries.
"""

import json
import sys
import os

# ANSI colors
BLUE = '\033[34m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
RED = '\033[31m'
MAGENTA = '\033[35m'
CYAN = '\033[36m'
RESET = '\033[0m'

# System overhead (system prompt + tools + memory)
SYSTEM_OVERHEAD = 21400


def get_git_info(git_path: str) -> str:
    """Get git branch and dirty status."""
    import subprocess
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


def parse_transcript(transcript_path: str) -> tuple[int, int]:
    """
    Parse transcript JSONL to get accurate token counts since last /compact.

    Returns (input_tokens, output_tokens) for current context window.
    """
    if not transcript_path or not os.path.exists(transcript_path):
        return (0, 0)

    input_tokens = 0
    output_tokens = 0

    try:
        with open(transcript_path, 'r') as f:
            lines = f.readlines()

        # Process lines in reverse to find last compact, then forward from there
        last_compact_idx = -1
        for i, line in enumerate(lines):
            try:
                entry = json.loads(line.strip())
                # Detect /compact command - it appears as a user message with "/compact"
                # or as a specific event type
                if entry.get('type') == 'user':
                    message = entry.get('message', {})
                    content = message.get('content', '')
                    if isinstance(content, str) and content.strip().startswith('/compact'):
                        last_compact_idx = i
                    elif isinstance(content, list):
                        for item in content:
                            if isinstance(item, dict) and item.get('type') == 'text':
                                if item.get('text', '').strip().startswith('/compact'):
                                    last_compact_idx = i
                                    break
                # Note: Don't treat summary events as compact boundaries.
                # Summary events can appear for various reasons, not just /compact.
                # Only actual /compact commands should reset the context count.
            except json.JSONDecodeError:
                continue

        # Process entries after last compact (or all if no compact found)
        start_idx = last_compact_idx + 1 if last_compact_idx >= 0 else 0

        for line in lines[start_idx:]:
            try:
                entry = json.loads(line.strip())

                # Look for API response with usage info
                if entry.get('type') == 'assistant':
                    message = entry.get('message', {})
                    usage = message.get('usage', {})

                    # Get token counts from this response
                    input_tokens = usage.get('input_tokens', 0)
                    output_tokens += usage.get('output_tokens', 0)

                    # Cache tokens contribute to context
                    input_tokens += usage.get('cache_creation_input_tokens', 0)
                    input_tokens += usage.get('cache_read_input_tokens', 0)

            except json.JSONDecodeError:
                continue

        return (input_tokens, output_tokens)

    except Exception:
        return (0, 0)


def get_context_from_json(data: dict) -> tuple[int, int, int]:
    """
    Get context info from JSON data passed by Claude Code.

    Returns (current_tokens, context_size, is_from_current_usage).
    """
    context_window = data.get('context_window', {})
    context_size = context_window.get('context_window_size', 200000)

    # Try current_usage first (most accurate for current state)
    current_usage = context_window.get('current_usage')
    if current_usage:
        input_tokens = current_usage.get('input_tokens', 0)
        cache_creation = current_usage.get('cache_creation_input_tokens', 0)
        cache_read = current_usage.get('cache_read_input_tokens', 0)
        current_tokens = input_tokens + cache_creation + cache_read
        return (current_tokens, context_size, True)

    # Fall back to total_input_tokens (cumulative, less accurate)
    total_input = context_window.get('total_input_tokens', 0)
    return (total_input, context_size, False)


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
    current_tokens, context_size, from_current = get_context_from_json(input_data)

    # Only fall back to transcript parsing if current_usage wasn't available
    # The JSON current_usage is authoritative; transcript parsing has edge cases
    # that can cause under-reporting (e.g., incorrect /compact boundary detection)
    if not from_current:
        transcript_path = input_data.get('transcript_path', '')
        if transcript_path:
            transcript_input, transcript_output = parse_transcript(transcript_path)
            if transcript_input > 0:
                current_tokens = transcript_input

    # Calculate percentage
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
