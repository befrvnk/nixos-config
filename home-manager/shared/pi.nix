{ pkgs, ... }:
let
  piSubagents = pkgs.fetchFromGitHub {
    owner = "nicobailon";
    repo = "pi-subagents";
    rev = "b5148abe4a81133658480fc1789efb78612eb0fa";
    sha256 = "10zmj461gnhypbsvc9mij65gli31inipn3ky2sj4cgf17gygx772";
  };

  piSettings = {
    defaultModel = "gpt-5.4";
    defaultProvider = "github-copilot";
    defaultThinkingLevel = "medium";
    hideThinkingBlock = true;
    packages = [
      "${piSubagents}"
    ];
  };
in
{
  home.packages = [
    pkgs.nodejs
    pkgs.pi-coding-agent
  ];

  home.file.".pi/agent/AGENTS.md".source = ./global-agent-context.md;
  home.file.".pi/agent/settings.json".text = builtins.toJSON piSettings;
}
