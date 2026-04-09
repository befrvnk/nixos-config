{ pkgs, ... }:
let
  piSettings = {
    defaultModel = "gpt-5.4";
    defaultProvider = "github-copilot";
    defaultThinkingLevel = "high";
    hideThinkingBlock = true;
  };

  piLspConfig = {
    servers = {
      java = {
        command = "${pkgs.jdt-language-server}/bin/jdtls";
        startupTimeoutMs = 60000;
      };
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
  home.packages = [
    pkgs.jdt-language-server
    pkgs.kotlin-lsp
    pkgs.nodejs
    pkgs.pi-coding-agent
    pkgs.typescript-language-server
  ];

  home.file.".pi/agent/AGENTS.md".source = ../global-agent-context.md;
  home.file.".pi/agent/extensions/subagents".source = ./extensions/subagents;
  home.file.".pi/agent/extensions/pi-lsp".source = ./extensions/pi-lsp;
  home.file.".pi/agent/extensions/system-theme-sync".source = ./extensions/system-theme-sync;
  home.file.".pi/agent/pi-lsp.json".text = builtins.toJSON piLspConfig;
  home.file.".pi/agent/settings.json".text = builtins.toJSON piSettings;
  home.file.".pi/agent/skills/exa-search".source = ./skills/exa-search;
}
