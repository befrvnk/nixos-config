{ ... }:
{
  programs.claude-code = {
    enable = true;

    # MCP Servers
    mcpServers = {
      context7 = {
        type = "http";
        url = "https://mcp.context7.com/mcp";
      };
    };

    # Note: Subagents are project-specific and located in .claude/agents/
    # They are version controlled with the project, not managed by Nix
  };

  # Claude Code global context
  # Manages global user-level context that applies to all projects
  home.file.".claude/CLAUDE.md".text = ''
    # Global Claude Code Context

    This file is automatically loaded by Claude Code for all projects.
    It imports project-specific AGENTS.md files when they exist.

    @./AGENTS.md
  '';
}
