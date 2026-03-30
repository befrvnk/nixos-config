{ pkgs, ... }:

{
  home.packages = [ pkgs.opencode ];

  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    plugin = [
      "@franlol/opencode-md-table-formatter@latest"
      "@simonwjackson/opencode-direnv"
    ];
  };

  xdg.configFile."opencode/AGENTS.md".source = ./global-agent-context.md;
}
