{ pkgs, ... }:

{
  home.packages = [
    pkgs.agent-of-empires
    pkgs.tmux
  ];

  home.file.".agent-of-empires/config.toml".text = ''
    [worktree]
    path_template = "../{repo-name}.{branch}"
  '';
}
