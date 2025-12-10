{ pkgs, ... }:
let
  statusLineScript = pkgs.runCommand "claude-statusline" { } ''
    cp ${
      pkgs.replaceVars ./statusline.sh {
        git = "${pkgs.git}/bin/git";
        jq = "${pkgs.jq}/bin/jq";
      }
    } $out
    chmod +x $out
  '';
in
{
  programs.claude-code = {
    enable = true;

    settings = {
      alwaysThinkingEnabled = true;
      statusLine = {
        type = "command";
        command = "${statusLineScript}";
        padding = 0;
      };
    };

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
