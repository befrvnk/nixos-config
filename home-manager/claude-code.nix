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

}
