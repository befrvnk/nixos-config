{ pkgs, ... }:

{
  home.packages = [
    pkgs.pi-coding-agent
  ];

  home.file.".pi/agent/AGENTS.md".source = ./global-agent-context.md;
}
