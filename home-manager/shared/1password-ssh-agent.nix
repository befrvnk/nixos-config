_:

{
  # 1Password's SSH agent exposes keys from the default Personal/Private/
  # Employee vaults only, unless an agent config file exists in which case that
  # file fully determines exposure. The hermi host key lives in the custom
  # "NixOS" vault, so it must be listed here explicitly.
  # https://www.1password.dev/ssh/agent/config
  home.file.".config/1Password/ssh/agent.toml".text = ''
    # 1Password SSH agent key selection
    # Creating this file overrides the default Personal/Private/Employee vault
    # behavior, so the default vault is re-listed explicitly below.

    # hermi Raspberry Pi host. Listed first so it is offered before the GitHub
    # keys, keeping authentication attempts well below the sshd MaxAuthTries
    # limit (default 6) on the Pi.
    [[ssh-keys]]
    item = "SSH Hermi"
    vault = "NixOS"

    # All SSH keys in the default Personal vault (GitHub auth/signing, id_rsa)
    [[ssh-keys]]
    vault = "Personal"
  '';
}
