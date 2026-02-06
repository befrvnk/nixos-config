{ pkgs, ... }:

let
  # 1Password SSH signing program path
  sshSignProgram =
    if pkgs.stdenv.isDarwin then
      "/Applications/1Password.app/Contents/MacOS/op-ssh-sign"
    else
      "/run/current-system/sw/bin/op-ssh-sign";
in
{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Frank Hermann";
        email = "hermann.frank@gmail.com";
        signingkey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJ+3hhn8MHxIuaTPFR6z+OPSL9YX5sBN80bct7GVspuz";
      };
      gpg.format = "ssh";
      gpg.ssh.program = sshSignProgram;
      commit.gpgsign = true;
      init.defaultBranch = "main";
      pull = {
        rebase = true;
      };
    };
  };
}
