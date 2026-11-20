# Agent signing keys

Framework and Darwin sign commits with separate machine-local Ed25519 keys
instead of 1Password. Signing works while 1Password is locked. SSH authentication
for operations such as `git push` still uses the 1Password agent.

## Darwin

Home Manager points Git directly at `~/.ssh/darwin-agent-signing` via `ssh-keygen`.
The private key is passphrase-free, mode `0600`, and kept on disk outside the
repository and the Nix store. Keep FileVault enabled for protection at rest.

On a fresh install or when rotating, generate a fresh key without overwriting an
existing one. In a POSIX shell:

```bash
umask 077
mkdir -p "$HOME/.ssh"
ssh-keygen -t ed25519 -N '' -C darwin-agent-signing -f "$HOME/.ssh/darwin-agent-signing"
```

For rotation, generate the replacement under a new filename and move it into
place when ready to switch. Update the `darwin-agent-signing` entry in
`home-manager/shared/git.nix` with the new **public** key, register it on GitHub
as a signing key, and apply with `nh darwin switch .`. Revoke the old signing key
on GitHub after switching. Never commit the private key.

## Framework

The private key is stored encrypted in `secrets/agent-signing.age` and decrypted
at activation to `/run/agenix/agent-signing` (tmpfs, owned by the primary user,
mode 0400). It never exists in plaintext on disk.

### Components

- `hosts/framework/agent-signing.nix`: agenix identity and secret definition.
- `home-manager/nixos/agent-signing.nix`: Git uses `ssh-keygen` and the
  decrypted key for signing.
- `home-manager/shared/git.nix`: the public key is listed in `allowed_signers`,
  so `git log --show-signature` verifies commits on both machines.
- `secrets/secrets.nix`: agenix recipient rules.

### Identity

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

### Rotating the agent key

1. Generate a new key with `ssh-keygen -t ed25519 -N ""` in tmpfs.
2. Encrypt it: `age -r <framework-age-pubkey> -o secrets/agent-signing.age <key>`.
3. Replace the public key in `home-manager/shared/git.nix`.
4. Delete the plaintext key, rebuild, and remove the old key from GitHub.

## GitHub

Register each machine's public key on GitHub as a **signing key** (Settings → SSH
and GPG keys → New SSH key → Key type: Signing Key). On Darwin, copy it with
`pbcopy < ~/.ssh/darwin-agent-signing.pub`. GitHub also requires the committer
email to be verified on the account that registers the key.

## Trade-off

Any process running as your user can sign commits without a prompt. Revoke the
affected signing key on GitHub if a machine is compromised, and remove it from
the shared `allowed_signers` list.
