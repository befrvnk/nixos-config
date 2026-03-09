{ pkgs, lib, ... }:

{
  home.packages = [
    pkgs.agent-of-empires
    pkgs.tmux
  ];

  home.activation.agent-of-empires-config = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p "$HOME/.agent-of-empires"
        rm -f "$HOME/.agent-of-empires/config.toml"
        cat > "$HOME/.agent-of-empires/config.toml" << 'AOEEOF'
    [theme]
    name = "catppuccin-latte"
    [worktree]
    path_template = "../{repo-name}.{branch}"
    AOEEOF
  '';
}
