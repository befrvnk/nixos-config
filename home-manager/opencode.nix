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
        model = "gemini-2.0-flash";
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
          "claude-3-7-sonnet"
          "claude-3-5-haiku"
        ];
      };
      google = {
        enabled = true;
        models = [
          "gemini-2.0-flash"
          "gemini-1.5-pro"
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

  # API Keys loaded dynamically from 1Password CLI at shell startup
  # This ensures keys are retrieved at runtime, not build time
  programs.zsh.initContent = ''
    # Load API keys from 1Password for OpenCode
    # To set up: Create items in 1Password with these names:
    # - "Anthropic API Key" with a field named "credential"
    # - "Gemini API Key" with a field named "credential"
    if command -v op &> /dev/null; then
      export ANTHROPIC_API_KEY="$(op read 'op://NixOS/Anthropic API Key/credential' 2>/dev/null || echo "")"
      export GEMINI_API_KEY="$(op read 'op://NixOS/Gemini API Key/credential' 2>/dev/null || echo "")"
    fi
  '';

  # Shell aliases for convenience
  programs.zsh.shellAliases = {
    ai = "opencode";
    "code-ai" = "opencode";
  };
}
