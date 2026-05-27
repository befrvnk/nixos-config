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

  piSettings = {
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
      pkgs.pi-coding-agent
      pkgs.typescript-language-server
    ];

    file = {
      ".pi/agent/AGENTS.md".source = ../global-agent-context.md;
      ".pi/agent/extensions/answer".source = runtimeExtension ./extensions/answer;
      ".pi/agent/extensions/enhanced-markdown".source = runtimeExtension ./extensions/enhanced-markdown;
      ".pi/agent/extensions/nav-tools".source = runtimeExtension ./extensions/nav-tools;
      ".pi/agent/extensions/nix-shell-fallback".source = runtimeExtension ./extensions/nix-shell-fallback;
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
