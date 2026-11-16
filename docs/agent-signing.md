# Agent signing key (Framework)

On the Framework, Git signs every commit with a machine-local ed25519 key instead
of 1Password. This lets agents and you commit without an approval prompt, and
it works while the 1Password vault is locked.

The private key is stored encrypted in `secrets/agent-signing.age` and decrypted
at activation to `/run/agenix/agent-signing` (tmpfs, owned by the primary user,
mode 0400). It never exists in plaintext on disk.

Darwin still signs with 1Password; this setup is Framework-only.

## Components

- `hosts/framework/agent-signing.nix`: agenix identity and secret definition.
- `home-manager/nixos/agent-signing.nix`: Git uses `ssh-keygen` and the
  decrypted key for signing.
- `home-manager/shared/git.nix`: the public key is listed in `allowed_signers`,
  so `git log --show-signature` verifies commits on both machines.
- `secrets/secrets.nix`: agenix recipient rules.

## Identity

`/var/lib/agenix/framework.key` is a root-only age identity, created once per
machine. It is not an SSH host key, so enabling `sshd` is not required.

Create it once on a fresh install. If `$XDG_RUNTIME_DIR/framework.age-key`
already exists, only verify it and install it; never generate a second key,
because the encrypted secret is bound to the first public key. Run this in a
normal terminal, not an agent session:

```nu
let key = $"($env.XDG_RUNTIME_DIR)/framework.age-key"
nix shell nixpkgs#age -c age-keygen -o $key
nix shell nixpkgs#age -c age-keygen -y $key
sudo mkdir -p -m 0700 /var/lib/agenix
sudo install -m 0400 -o root -g root $key /var/lib/agenix/framework.key
rm $key
```

Put the printed public key into `secrets/secrets.nix` and re-encrypt the secret
before the next switch.

## Rotating the agent key

1. Generate a new key with `ssh-keygen -t ed25519 -N ""` in tmpfs.
2. Encrypt it: `age -r <framework-age-pubkey> -o secrets/agent-signing.age <key>`.
3. Replace the public key in `home-manager/shared/git.nix`.
4. Delete the plaintext key, rebuild, and remove the old key from GitHub.

## GitHub

Register the agent public key on GitHub as a **signing key** (Settings → SSH and
GPG keys → New SSH key → Key type: Signing Key). Commits from the Framework
then show as verified.

## Trade-off

Any process running as your user can sign commits while the Framework is
running, with no prompt. Revoke the key on GitHub if the machine is compromised.
