{ pkgs, config, ... }:

{
  # Install OpenCode from nixpkgs
  home.packages = with pkgs; [
    opencode
  ];

  # OpenCode configuration file
  xdg.configFile."opencode/.opencode.json".text = builtins.toJSON {
    # Agent configurations
    agents = {
      coder = {
        model = "claude-sonnet-4-5";
        maxTokens = 8000;
        temperature = 0.7;
      };
      architect = {
        model = "claude-sonnet-4-5";
        maxTokens = 4000;
      };
      reviewer = {
        model = "gemini-2.5-flash";
        maxTokens = 4000;
      };
    };

    # Default model preferences
    defaultModel = "claude-sonnet-4-5";

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
