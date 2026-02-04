{ pkgs, ... }:

{
  home.packages = [ pkgs.worktrunk ];

  xdg.configFile."worktrunk/config.toml".text = ''
    [commit]
    stage = "tracked"

    # Auto-allow direnv in new worktrees
    post-create = "direnv allow"
  '';
}
