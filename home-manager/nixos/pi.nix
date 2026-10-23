{ lib, pkgs, ... }:
{
  home.packages = [
    # Pi compiled ahead of time to a native executable (separate install from
    # pi-coding-agent; shares ~/.pi/agent with Pi). NixOS-only for now.
    pkgs.pi-bolt
  ];

  # NixOS-only pi defaults: use DeepSeek V4 Flash on OpenRouter as the standard
  # model, always routing to the fastest provider. Darwin keeps the shared
  # GitHub Copilot default.
  pi = {
    defaultModel = "deepseek/deepseek-v4-flash-0731";
    defaultProvider = "openrouter";
    defaultThinkingLevel = "high";
    openRouterFastRouting = true;
    openRouterFastModel = "deepseek/deepseek-v4-flash-0731";
  };
}
