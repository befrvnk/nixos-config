{ lib, pkgs, ... }:
let
  # Deploy only runtime files to ~/.pi; drop unit tests and dev docs that pi never loads.
  runtimeExtension =
    src:
    lib.cleanSourceWith {
      inherit src;
      name = "pi-ext-${baseNameOf src}";
      filter =
        path: type:
        let
          base = baseNameOf path;
        in
        type == "directory"
        || !(lib.hasSuffix ".test.ts" base || lib.hasSuffix ".test.mjs" base || lib.hasSuffix ".md" base);
    };

  piCopilotLiveModelsRefresh = pkgs.writeShellScriptBin "pi-copilot-live-models-refresh" ''
    set -u

    should_refresh=1
    for arg in "$@"; do
      case "$arg" in
        --help|-h|--version|version)
          should_refresh=0
          ;;
      esac
    done

    case "''${1:-}" in
      auth)
        should_refresh=0
        ;;
    esac

    if [ "$should_refresh" != 1 ] || [ "''${PI_COPILOT_LIVE_MODELS:-1}" = 0 ]; then
      exit 0
    fi

    if [ "''${PI_COPILOT_LIVE_MODELS_DEBUG:-0}" = 1 ]; then
      ${pkgs.nodejs}/bin/node --experimental-strip-types \
        "$HOME/.pi/agent/extensions/copilot-live-models/write-models-json.ts"
    else
      ${pkgs.nodejs}/bin/node --experimental-strip-types \
        "$HOME/.pi/agent/extensions/copilot-live-models/write-models-json.ts" >/dev/null 2>&1
    fi
  '';

  piWithCopilotLiveModels = pkgs.writeShellScriptBin "pi" ''
    if ${piCopilotLiveModelsRefresh}/bin/pi-copilot-live-models-refresh "$@"; then
      export PI_COPILOT_LIVE_MODELS_SKIP_EXTENSION=1
    fi
    exec ${pkgs.pi-coding-agent}/bin/pi "$@"
  '';

  piSettings = {
    compaction = {
      enabled = true;
      # GitHub Copilot's long-context tier reports 922k prompt tokens + 128k output tokens.
      # Keep Pi's auto-compaction threshold aligned with that prompt budget.
      keepRecentTokens = 20000;
      reserveTokens = 128000;
    };
    defaultModel = "gpt-5.5";
    defaultProvider = "github-copilot";
    defaultThinkingLevel = "high";
    hideThinkingBlock = true;
  };

  piLspConfig = {
    servers = {
      kotlin = {
        args = [ "--stdio" ];
        command = "${pkgs.kotlin-lsp}/bin/kotlin-lsp";
        startupTimeoutMs = 45000;
      };
      nix = {
        args = [ "--stdio" ];
        command = "${pkgs.nil}/bin/nil";
        startupTimeoutMs = 15000;
      };
      typescript = {
        args = [ "--stdio" ];
        command = "${pkgs.typescript-language-server}/bin/typescript-language-server";
        startupTimeoutMs = 15000;
      };
    };
  };
in
{
  home = {
    packages = [
      pkgs.kotlin-lsp
      pkgs.nodejs
      piCopilotLiveModelsRefresh
      (lib.hiPrio piWithCopilotLiveModels)
      pkgs.pi-coding-agent
      pkgs.typescript-language-server
    ];

    file = {
      ".pi/agent/AGENTS.md".source = ../global-agent-context.md;
      ".pi/agent/extensions/answer".source = runtimeExtension ./extensions/answer;
      ".pi/agent/extensions/copilot-live-models".source =
        runtimeExtension ./extensions/copilot-live-models;
      ".pi/agent/extensions/enhanced-markdown".source = runtimeExtension ./extensions/enhanced-markdown;
      ".pi/agent/extensions/nav-tools".source = runtimeExtension ./extensions/nav-tools;
      ".pi/agent/extensions/pi-lsp".source = runtimeExtension ./extensions/pi-lsp;
      ".pi/agent/extensions/read-path-ui".source = runtimeExtension ./extensions/read-path-ui;
      ".pi/agent/extensions/search-tools".source = runtimeExtension ./extensions/search-tools;
      ".pi/agent/extensions/subagents".source = runtimeExtension ./extensions/subagents;
      ".pi/agent/extensions/system-theme-sync".source = runtimeExtension ./extensions/system-theme-sync;
      ".pi/agent/pi-lsp.json".text = builtins.toJSON piLspConfig;
      ".pi/agent/settings.json".text = builtins.toJSON piSettings;
    };
  };
}
