{ pkgs, lib, ... }:
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

  pluginId = "kotlin-lsp@claude-plugins-official";
in
{
  programs.claude-code = {
    enable = true;

    settings = {
      alwaysThinkingEnabled = true;
      env = {
        ENABLE_LSP_TOOL = "1";
      };
      enabledPlugins = {
        ${pluginId} = true;
      };
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
      # Nix-managed Kotlin LSP plugin — registered via activation script below
      ".claude/plugins/kotlin-lsp/.claude-plugin/plugin.json".text = builtins.toJSON {
        name = "kotlin-lsp";
        description = "Kotlin language server integration";
        version = "1.0.0";
        lspServers = {
          kotlin-lsp = {
            command = "${pkgs.kotlin-lsp}/bin/kotlin-lsp";
            args = [ "--stdio" ];
            extensionToLanguage = {
              ".kt" = "kotlin";
              ".kts" = "kotlin";
            };
            startupTimeout = 120000;
          };
        };
      };
      ".claude/plugins/kotlin-lsp/.lsp.json".text = builtins.toJSON {
        kotlin-lsp = {
          command = "${pkgs.kotlin-lsp}/bin/kotlin-lsp";
          args = [ "--stdio" ];
          extensionToLanguage = {
            ".kt" = "kotlin";
            ".kts" = "kotlin";
          };
          startupTimeout = 120000;
        };
      };

      # Global Claude Code skills (available in all projects)
      ".claude/skills/remember/SKILL.md".source = ./skills/remember.md;
    };

    # Register the Nix-managed plugin in installed_plugins.json after each rebuild.
    # This ensures Claude Code loads from ~/.claude/plugins/kotlin-lsp (always
    # pointing to the current pkgs.kotlin-lsp) instead of a stale marketplace cache.
    activation.registerKotlinLsp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      pluginsFile="$HOME/.claude/plugins/installed_plugins.json"
      if [ ! -f "$pluginsFile" ]; then
        printf '{"version":2,"plugins":{}}\n' > "$pluginsFile"
      fi
      tmpFile=$(mktemp)
      ${pkgs.jq}/bin/jq --arg id "${pluginId}" --arg path "$HOME/.claude/plugins/kotlin-lsp" '
        .plugins[$id] = [{
          "scope": "user",
          "installPath": $path,
          "version": "1.0.0",
          "installedAt": "2026-02-20T13:27:13.362Z",
          "lastUpdated": "2026-03-02T00:00:00.000Z"
        }]
      ' "$pluginsFile" > "$tmpFile" && mv "$tmpFile" "$pluginsFile"
    '';
  };
}
