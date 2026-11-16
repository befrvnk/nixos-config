{ lib, pkgs, ... }:

{
  # Framework signs with the machine's agenix key instead of 1Password (see
  # docs/agent-signing.md). Verification still uses the shared allowed_signers file.
  programs.git.settings = {
    gpg.ssh.program = lib.mkForce "${pkgs.openssh}/bin/ssh-keygen";
    user.signingkey = lib.mkForce "/run/agenix/agent-signing";
  };
}
