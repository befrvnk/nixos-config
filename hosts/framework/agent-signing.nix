{ hostConfig, ... }:

{
  # Root-only age identity, created once per machine (see docs/agent-signing.md).
  # Not an SSH host key: enabling sshd just to decrypt would add an attack surface.
  age.identityPaths = [ "/var/lib/agenix/framework.key" ];

  age.secrets.agent-signing = {
    file = ../../secrets/agent-signing.age;
    owner = hostConfig.primaryUser;
    mode = "0400";
  };
}
