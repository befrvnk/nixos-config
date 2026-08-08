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
        || !(
          lib.hasSuffix ".test.ts" base
          || lib.hasSuffix ".test.mjs" base
          || lib.hasSuffix ".md" base
          || base == "migrate-legacy-models-json.mjs"
        );
    };

  piSettings = {
    compaction = {
      enabled = true;
      # GitHub Copilot's long-context tier reports 922k prompt tokens + 128k output tokens.
      # Keep Pi's auto-compaction threshold aligned with that prompt budget.
      keepRecentTokens = 20000;
      reserveTokens = 128000;
    };
    defaultModel = "deepseek/deepseek-v4-flash-0731";
    defaultProvider = "openrouter";
    defaultThinkingLevel = "high";
    hideThinkingBlock = true;
  };

  # Route the default model over OpenRouter: prefer the cheapest provider that
  # still meets a p50 throughput of at least 50 tokens/s. `sort: price` disables
  # load balancing and tries endpoints lowest-cost first, while
  # `preferred_min_throughput` deprioritizes sub-50tps providers behind those
  # meeting the floor.
  piModels = {
    providers.openrouter.modelOverrides = {
      "deepseek/deepseek-v4-flash-0731".compat.openRouterRouting = {
        sort = {
          by = "price";
          partition = "model";
        };
        preferred_min_throughput = {
          p50 = 50;
        };
      };
    };
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
    activation.removeLegacyCopilotModelsJson = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      ${pkgs.nodejs}/bin/node ${./extensions/copilot-live-models/migrate-legacy-models-json.mjs} \
        "$HOME/.pi/agent/models.json" || true
    '';

    packages = [
      pkgs.kotlin-lsp
      pkgs.pi-coding-agent
      pkgs.typescript-language-server
    ];

    file = {
      ".pi/agent/AGENTS.md".source = ../global-agent-context.md;
      ".pi/agent/extensions/answer".source = runtimeExtension ./extensions/answer;
      ".pi/agent/extensions/bash-output-control".source =
        runtimeExtension ./extensions/bash-output-control;
      ".pi/agent/extensions/copilot-live-models".source =
        runtimeExtension ./extensions/copilot-live-models;
      ".pi/agent/extensions/enhanced-markdown".source = runtimeExtension ./extensions/enhanced-markdown;
      ".pi/agent/extensions/nav-tools".source = runtimeExtension ./extensions/nav-tools;
      ".pi/agent/extensions/pi-lsp".source = runtimeExtension ./extensions/pi-lsp;
      ".pi/agent/extensions/read-path-ui".source = runtimeExtension ./extensions/read-path-ui;
      ".pi/agent/extensions/search-tools".source = runtimeExtension ./extensions/search-tools;
      ".pi/agent/extensions/subagents".source = runtimeExtension ./extensions/subagents;
      ".pi/agent/extensions/system-theme-sync".source = runtimeExtension ./extensions/system-theme-sync;
      ".pi/agent/models.json".text = builtins.toJSON piModels;
      ".pi/agent/pi-lsp.json".text = builtins.toJSON piLspConfig;
      ".pi/agent/settings.json".text = builtins.toJSON piSettings;
    };
  };
}
