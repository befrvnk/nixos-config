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

  home = {
    # Kotlin LSP for Claude Code intelligence
    packages = [ pkgs.kotlin-lsp ];

    file = {
      # LSP plugins (local, no marketplace needed)
      ".claude/plugins/kotlin-lsp/.claude-plugin/plugin.json".text = builtins.toJSON {
        name = "kotlin-lsp";
        description = "Kotlin language server integration";
      };
      ".claude/plugins/kotlin-lsp/.lsp.json".text = builtins.toJSON {
        kotlin = {
          command = "${pkgs.kotlin-lsp}/bin/kotlin-lsp";
          extensionToLanguage = {
            ".kt" = "kotlin";
            ".kts" = "kotlin";
          };
        };
      };

      # Global Claude Code skills (available in all projects)
      ".claude/skills/remember/SKILL.md".source = ./skills/remember.md;
    };
  };
}
