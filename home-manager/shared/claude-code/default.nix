{
  config,
  pkgs,
  lib,
  ...
}:
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

  homeDir = config.home.homeDirectory;
  marketplaceName = "local";
  marketplaceDir = "${homeDir}/.claude/plugins/marketplaces/${marketplaceName}";

  # Shared LSP configs (used in marketplace.json and installed_plugins.json)
  nixLspConfig = {
    command = "${pkgs.nil}/bin/nil";
    args = [ "--stdio" ];
    extensionToLanguage = {
      ".nix" = "nix";
    };
    startupTimeout = 30000;
  };

  kotlinLspConfig = {
    command = "${pkgs.kotlin-lsp}/bin/kotlin-lsp";
    args = [ "--stdio" ];
    extensionToLanguage = {
      ".kt" = "kotlin";
      ".kts" = "kotlin";
    };
    startupTimeout = 120000;
  };

  # Both plugins use the local marketplace
  kotlinPluginId = "kotlin-lsp@${marketplaceName}";
  nixPluginId = "nix-lsp@${marketplaceName}";
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
        ${kotlinPluginId} = true;
        ${nixPluginId} = true;
      };
      extraKnownMarketplaces = {
        ${marketplaceName} = {
          source = {
            source = "directory";
            path = marketplaceDir;
          };
        };
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
    packages = [
      pkgs.kotlin-lsp
    ];

    file = {
      # --- Local marketplace with all LSP plugins ---
      # Schema matches claude-plugins-official: owner + inline lspServers per plugin
      ".claude/plugins/marketplaces/${marketplaceName}/.claude-plugin/marketplace.json".text =
        builtins.toJSON
          {
            "$schema" = "https://anthropic.com/claude-code/marketplace.schema.json";
            name = marketplaceName;
            description = "Local Nix-managed plugin marketplace";
            owner = {
              name = "local";
            };
            plugins = [
              {
                name = "kotlin-lsp";
                description = "Kotlin language server for code intelligence";
                version = "1.0.0";
                author = {
                  name = "local";
                };
                source = "./plugins/kotlin-lsp";
                category = "development";
                strict = false;
                lspServers = {
                  kotlin-lsp = kotlinLspConfig;
                };
              }
              {
                name = "nix-lsp";
                description = "Nix language server (nil) integration";
                version = "1.0.0";
                author = {
                  name = "local";
                };
                source = "./plugins/nix-lsp";
                category = "development";
                strict = false;
                lspServers = {
                  nix-lsp = nixLspConfig;
                };
              }
            ];
          };

      # Plugin directories must exist for marketplace source paths
      ".claude/plugins/marketplaces/${marketplaceName}/plugins/kotlin-lsp/README.md".text = ''
        # kotlin-lsp

        Kotlin language server integration for Claude Code.
        Managed by Nix via home-manager.
      '';
      ".claude/plugins/marketplaces/${marketplaceName}/plugins/nix-lsp/README.md".text = ''
        # nix-lsp

        Nix language server (nil) integration for Claude Code.
        Managed by Nix via home-manager.
      '';

      # Global Claude Code skills (available in all projects)
      ".claude/skills/remember/SKILL.md".source = ./skills/remember.md;
    };

    # Declaratively write installed_plugins.json on every rebuild.
    # Full replacement (not merge) so removed plugins are automatically cleaned up.
    activation.registerLspPlugins = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      pluginsFile="$HOME/.claude/plugins/installed_plugins.json"
      mkdir -p "$(dirname "$pluginsFile")"

      cat > "$pluginsFile" << 'PLUGINS_EOF'
      ${builtins.toJSON {
        version = 2;
        plugins = {
          ${kotlinPluginId} = [
            {
              scope = "user";
              installPath = "${marketplaceDir}/plugins/kotlin-lsp";
              version = "1.0.0";
              installedAt = "2026-02-20T13:27:13.362Z";
              lastUpdated = "2026-03-02T00:00:00.000Z";
            }
          ];
          ${nixPluginId} = [
            {
              scope = "user";
              installPath = "${marketplaceDir}/plugins/nix-lsp";
              version = "1.0.0";
              installedAt = "2026-03-02T00:00:00.000Z";
              lastUpdated = "2026-03-02T00:00:00.000Z";
            }
          ];
        };
      }}
      PLUGINS_EOF

      # Clear orphaned_at markers that Claude Code sets when plugin IDs change
      for cacheDir in \
        "$HOME/.claude/plugins/cache/${marketplaceName}/kotlin-lsp/1.0.0" \
        "$HOME/.claude/plugins/cache/${marketplaceName}/nix-lsp/1.0.0"; do
        mkdir -p "$cacheDir"
        rm -f "$cacheDir/.orphaned_at"
      done
    '';
  };
}
