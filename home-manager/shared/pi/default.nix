{ pkgs, ... }:
let
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
      ".pi/agent/extensions/answer".source = ./extensions/answer;
      ".pi/agent/extensions/nav-tools".source = ./extensions/nav-tools;
      ".pi/agent/extensions/nix-shell-fallback".source = ./extensions/nix-shell-fallback;
      ".pi/agent/extensions/pi-lsp".source = ./extensions/pi-lsp;
      ".pi/agent/extensions/subagents".source = ./extensions/subagents;
      ".pi/agent/extensions/system-theme-sync".source = ./extensions/system-theme-sync;
      ".pi/agent/pi-lsp.json".text = builtins.toJSON piLspConfig;
      ".pi/agent/settings.json".text = builtins.toJSON piSettings;
      ".pi/agent/skills/exa-search".source = ./skills/exa-search;
    };
  };
}
