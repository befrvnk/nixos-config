{ pkgs, ... }:

{
  home.packages = [
    pkgs.pi-coding-agent
  ];

  xdg.configFile."pi/agent/AGENTS.md".source = ./global-agent-context.md;
}
