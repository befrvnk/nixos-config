{ config, ... }:

{
  programs.opencode = {
    enable = true;
  };

  # OpenCode configuration file with Claude Code workflow
  xdg.configFile."opencode/.opencode.json".text = builtins.toJSON {
    # Default model preferences - use Gemini Pro for general tasks
    defaultModel = "gemini-2.5-pro";

    # UI preferences
    ui = {
      theme = "dark";
      editor = "zed";
    };

    # Provider configurations
    providers = {
      anthropic = {
        enabled = true;
        models = [
          "claude-sonnet-4-5"
          "claude-haiku-4-5"
        ];
      };
      google = {
        enabled = true;
        models = [
          "gemini-2.5-flash"
          "gemini-2.5-pro"
        ];
      };
    };
  };

  # Deploy agent markdown files
  xdg.configFile."opencode/agent/coder.md".source = ./agents/coder.md;
  xdg.configFile."opencode/agent/planner.md".source = ./agents/planner.md;
  xdg.configFile."opencode/agent/quick.md".source = ./agents/quick.md;
  xdg.configFile."opencode/agent/reviewer.md".source = ./agents/reviewer.md;

  # Deploy command files
  xdg.configFile."opencode/command/commit.md".source = ./commands/commit.md;

  # Environment variables for configuration
  home.sessionVariables = {
    # Set Zed as the external editor for OpenCode
    EDITOR = "zed";

    # OpenCode configuration
    OPENCODE_CONFIG_DIR = "${config.xdg.configHome}/opencode";
  };

  # Shell aliases for convenience
  programs.zsh.shellAliases = {
    ai = "opencode";
    "code-ai" = "opencode";
  };
}
