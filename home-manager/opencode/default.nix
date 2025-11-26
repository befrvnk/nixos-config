{ config, pkgs, ... }:

let
  anytype = import ../mcp/anytype.nix { inherit pkgs; };
  opencode-wrapped = anytype.wrapWithAnytypeKey {
    package = pkgs.opencode;
    name = "opencode";
  };
in
{
  programs.opencode = {
    enable = true;
    package = opencode-wrapped;

    settings = {
      model = "google/gemini-2.5-pro";

      mcp = {
        context7 = {
          type = "remote";
          url = "https://mcp.context7.com/mcp";
        };
        anytype = anytype.anytype-mcp-config anytype.anytype-mcp-wrapper;
      };
    };

    agents = {
      "coder.md" = ./agents/coder.md;
      "planner.md" = ./agents/planner.md;
      "quick.md" = ./agents/quick.md;
      "reviewer.md" = ./agents/reviewer.md;
    };

    commands = {
      "commit.md" = ./commands/commit.md;
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
