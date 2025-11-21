{ ... }:
{
  # Claude Code configuration
  # Manages global user-level context that applies to all projects

  home.file.".claude/CLAUDE.md".text = ''
    # Global Claude Code Context

    This file is automatically loaded by Claude Code for all projects.
    It imports project-specific AGENTS.md files when they exist.

    @./AGENTS.md
  '';
}
