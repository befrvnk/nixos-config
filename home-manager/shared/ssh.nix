{ pkgs, ... }:

let
  # 1Password SSH agent socket path differs by platform
  agentPath =
    if pkgs.stdenv.isDarwin then
      ''"~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"''
    else
      "~/.1password/agent.sock";
in
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings."*" = {
      IdentityAgent = agentPath;
    };

    # Ghostty sets TERM=xterm-ghostty, which the minimal hermi image does not
    # have terminfo for (ncurses tools report "unknown terminal type"). Send a
    # portable TERM instead; hermi's sshd accepts it via AcceptEnv.
    matchBlocks.hermi = {
      user = "frank";
      setEnv = {
        TERM = "xterm-256color";
      };
    };
  };
}
