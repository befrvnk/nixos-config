{ lib, ... }:
{
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
