{
  config,
  lib,
  pkgs,
  ...
}:

{
  # Read the Mac's private key directly; the 1Password SSH agent still handles authentication.
  programs.git.settings = {
    gpg.ssh.program = lib.mkForce "${pkgs.openssh}/bin/ssh-keygen";
    user.signingkey = lib.mkForce "${config.home.homeDirectory}/.ssh/darwin-agent-signing";
  };
}
