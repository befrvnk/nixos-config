{ pkgs, ... }:
let
  # Python statusline script with accurate context tracking
  statusLineScript = pkgs.writers.writePython3Bin "claude-statusline" {
    flakeIgnore = [ "E501" ]; # Ignore line length warnings
  } (builtins.readFile ./statusline.py);

  # Wrapper to ensure git is in PATH
  statusLineWrapper = pkgs.writeShellScript "claude-statusline-wrapper" ''
    export GIT_PATH="${pkgs.git}/bin/git"
    exec ${statusLineScript}/bin/claude-statusline "$@"
  '';
in
{
  programs.claude-code = {
    enable = true;

    settings = {
      alwaysThinkingEnabled = true;
      statusLine = {
        type = "command";
        command = "${statusLineWrapper}";
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
