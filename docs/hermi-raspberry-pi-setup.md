# Hermi Raspberry Pi Nanobot Setup

This document describes building, provisioning, and operating `hermi`: a
headless Raspberry Pi 4 (8 GB) running Nanobot — a lightweight self-hosted AI
agent with a browser WebUI — with OpenRouter as the model provider.

The configuration is declared in this repository and is built on the
Framework laptop (`x86_64-linux`). The target is `aarch64-linux`.

## Design

- **Host:** `hermi`
- **Hardware:** Raspberry Pi 4
- **Primary user:** `frank`
- **Storage:** microSD card
- **First boot networking:** Ethernet through the FRITZ!Box
- **Normal networking:** Wi-Fi, configured after first boot
- **Remote administration:** SSH with the dedicated 1Password-managed Ed25519 key
- **Agent:** Nanobot (WebUI + gateway), replaces the former hermes-agent
- **State directory:** `/var/lib/nanobot`
- **WebUI:** `http://hermi:9119` on the home LAN, protected by a browser token
- **Model provider:** OpenRouter

Do not configure a FRITZ!Box port-forward for SSH or the dashboard. The
initial setup is intended for the trusted home LAN only. For access away from
home, add Tailscale or use the FRITZ!Box WireGuard VPN later.

## Repository Layout

The relevant configuration is:

- `hosts/hermi/default.nix` — Pi hardware, SSH, networking, and Nanobot
- `flake.nix` — `nixosConfigurations.hermi`
- `hosts/framework/default.nix` — enables AArch64 emulation needed to build the image

The Pi configuration uses `nixos-raspberrypi` for the Raspberry Pi 4 board
profile, vendor kernel, firmware, bootloader, SD-card image module, and its
Cachix binary cache. This avoids compiling the Pi vendor kernel through QEMU.

## Prerequisites

Before building, have:

- the Framework running NixOS and a current checkout of this repository;
- a Raspberry Pi 4, power supply, microSD card, and Ethernet cable;
- Ethernet connected to the FRITZ!Box for first boot;
- the `hermi` SSH key available through the 1Password SSH agent on the Framework;
- an OpenRouter API key, but do not add it to Git or a Nix expression.

Confirm that the 1Password SSH agent offers the `hermi` public key:

```bash
SSH_AUTH_SOCK="$HOME/.1password/agent.sock" ssh-add -L
```

The output should contain the dedicated `ssh-ed25519` public key configured in
`hosts/hermi/default.nix`.

Plain `ssh-add -L` reads the default `SSH_AUTH_SOCK` (often GNOME Keyring on
NixOS), which is not the agent SSH actually uses: `~/.ssh/config` sets
`IdentityAgent` to the 1Password socket (`home-manager/shared/ssh.nix`).

The `hermi` key lives in the custom `NixOS` vault. The 1Password SSH agent
only exposes keys from the default `Personal`/`Private`/`Employee` vaults
unless an agent config file (`~/.config/1Password/ssh/agent.toml`) lists more;
that file is managed declaratively by
`home-manager/shared/1password-ssh-agent.nix`.

## Build the SD Image on the Framework

The Framework is x86_64 while the Pi is AArch64. The Framework configuration
enables QEMU/binfmt emulation for `aarch64-linux`.

### 1. Apply the Framework configuration

Run this on the Framework after updating the repository:

```bash
rebuild switch
```

This is required once before the Framework can execute target AArch64 build
tools. It may request substantial downloads on the first run.

### 2. Build the Pi image

```bash
nix build .#nixosConfigurations.hermi.config.system.build.sdImage \
  --accept-flake-config \
  --option extra-substituters https://nixos-raspberrypi.cachix.org \
  --option extra-trusted-public-keys \
    nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI=
```

The image downloads the prebuilt Pi vendor kernel and firmware from the
`nixos-raspberrypi` Cachix cache. The explicit cache options make the command
work even if the Framework has not yet applied the repository's updated Nix
cache configuration. Nix may still assemble the custom image and fetch many
source artifacts, but it must not compile `linux-rpi` locally.

The result is available at:

```text
result/sd-image/*.img.zst
```

## Flash the MicroSD Card

Use Raspberry Pi Imager or another image-writing tool. If using the command
line, first identify the microSD card carefully:

```bash
lsblk
```

Unmount its partitions, then write the image. Replace `/dev/sdX` with the
whole microSD device, not one of its partitions and never the Framework's
internal disk:

```bash
sudo umount /dev/sdX* 2>/dev/null || true
zstd -d -c result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

If `zstd` is unavailable, run the command through a temporary Nix shell:

```bash
nix shell nixpkgs#zstd --command bash -c \
  'zstd -d -c result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress; sync'
```

Remove the card safely, insert it into the Pi, attach Ethernet, and power it
on.

## First Boot and SSH

Find the Pi's DHCP lease/IP address in the FRITZ!Box interface. Connect from
the Framework:

```bash
ssh frank@<pi-ip-address>
```

The Pi accepts only public-key SSH authentication. Password authentication and
root SSH login are disabled. The initial image has no password hash for
`frank`, so `sudo` is intentionally passwordless and access to the SSH key is
the administrative credential. If a local password is configured later, enable
`security.sudo.wheelNeedsPassword` in `hosts/hermi/default.nix` and rebuild.

If 1Password does not offer the expected key,
check the SSH-agent configuration and repeat:

```bash
SSH_AUTH_SOCK="$HOME/.1password/agent.sock" ssh-add -L
```

After local DNS is working, the host name may be usable directly:

```bash
ssh frank@hermi
```

## Configure Wi-Fi

Wi-Fi hardware and NetworkManager are enabled declaratively, but the Wi-Fi
password is intentionally not embedded in the image, Nix store, or Git
repository.

While connected through Ethernet, list networks and join the home network:

```bash
sudo nmcli device wifi list
sudo nmcli device wifi connect "<SSID>" password "<Wi-Fi password>"
```

Verify the connection before unplugging Ethernet:

```bash
nmcli connection show --active
ip address
```

NetworkManager persists the connection profile locally and reconnects after
future boots.

## Configure Nanobot Secrets

The image intentionally starts with the WebUI bound to localhost and no model
configured. One secret drives the WebUI's LAN mode, stored in
`/var/lib/nanobot/env` and loaded by the `nanobot` systemd service:

- `NANOBOT_WS_TOKEN` — enables LAN entry to the WebUI (a browser token is
  required). Without it the WebUI stays on `127.0.0.1` only.

Generate a token (the Pi image has no OpenSSL; the kernel CSPRNG through
coreutils is equivalent):

```bash
head -c 32 /dev/urandom | base64 -w0
```

Create the environment file:

```bash
sudo tee /var/lib/nanobot/env >/dev/null <<'EOF'
NANOBOT_WS_TOKEN=replace-with-the-generated-secret
EOF
sudo chown nanobot:nanobot /var/lib/nanobot/env
sudo chmod 0600 /var/lib/nanobot/env
```

Then apply it: rerun activation or reboot, so the WebUI config is regenerated
in LAN mode (`host` 0.0.0.0, port 9119, token required). The running config
lives in `/var/lib/nanobot/.nanobot/config.json`; remove the env var and
restart to go localhost-only again.

Never put these values in `hosts/hermi/default.nix` or a committed file: Nix
expressions become readable through the Nix store.

The `nanobot` runtime is a pinned PyPI venv (`nanobot-ai==0.3.0`) created by
the first activation and reused afterwards; the service runs as the `nanobot`
user.

Check status and logs if needed:

```bash
systemctl status nanobot
journalctl -u nanobot -f
```

## Use the WebUI from Android

Connect the Android device to the same home Wi-Fi, then browse to:

```text
http://hermi:9119
```

If the name does not resolve, use the Pi's current LAN address instead:

```text
http://<pi-ip-address>:9119
```

Enter the browser token (`NANOBOT_WS_TOKEN`) when prompted. Add the page to
the browser's home screen for an app-like launcher.

The WebUI listens on port `9119`, which is open in the Pi firewall. It remains
inaccessible from the public Internet unless a router port-forward is
deliberately created; do not create one.

## Configure the Model in the WebUI

On first launch, use **Settings → Models** in the WebUI:

- Add an OpenAI-compatible provider:
  - Base URL: `https://openrouter.ai/api/v1`
  - API key: your OpenRouter key (also settable via `OPENAI_API_KEY` and
    `OPENAI_BASE_URL` in `/var/lib/nanobot/env`)
- Pick a model preset, for example a `deepseek/*` model available via
  OpenRouter.

Send a test message in a new topic. See Routine Operations below for the usual
commands.

## Routine Operations

### Service status and logs

```bash
systemctl status nanobot
journalctl -u nanobot -f
```

### Restart the service after changing `/var/lib/nanobot/env`

```bash
sudo systemctl restart nanobot
```

### Update the Pi configuration

Make and commit changes in this repository, then build a new SD image from the
Framework for a fresh installation. For an already-installed Pi, use the
repository checkout on the Pi and run:

```bash
sudo nixos-rebuild switch --flake .#hermi --accept-flake-config
```

The nanobot service is declarative in `hosts/hermi/default.nix` (user, venv
bootstrap, systemd unit). Change it there and rebuild rather than running
`nanobot` CLI setup commands with stateful side effects on the Pi.

## Updating an Installed Pi

The SD image is only for first installation. Do not reflash the card for normal
configuration updates.

The simplest update workflow is to copy or clone this repository onto the Pi,
then rebuild natively:

```bash
cd ~/nixos-config
git pull
sudo nixos-rebuild switch --flake .#hermi --accept-flake-config
```

For a private repository, use a Git deploy key or copy the checkout from the
Framework instead of placing a personal GitHub token on the Pi. For example,
from the Framework:

```bash
rsync -a --delete --exclude .git /path/to/nixos-config/ frank@hermi:~/nixos-config/
ssh frank@hermi 'cd ~/nixos-config && sudo nixos-rebuild switch --flake .#hermi --accept-flake-config'
```

The Framework can also build the AArch64 closure through binfmt/QEMU and deploy
it to the Pi without keeping a checkout there:

```bash
nixos-rebuild switch --flake .#hermi \
  --target-host frank@hermi \
  --elevate=sudo \
  --accept-flake-config
```

This is different from a remote *builder*: the Framework performs the build,
copies its result to the target Pi, then activates it remotely. It is the
recommended remote deployment workflow until a separate native AArch64 builder
is available.

> First remote deploy gotcha: the target store rejects locally-built unsigned
> paths (e.g. generated config files) during the closure copy. Bootstrap once
> by rebuilding natively on the Pi (rsync the checkout, then
> `sudo nixos-rebuild switch --flake .#hermi --accept-flake-config`).
> Afterwards, set up a signing key pair (Framework
> `nix.settings.secretKeyFiles` + hermi `nix.settings.trustedPublicKeys`) to
> make plain remote deploys work.

## Future Improvements

- Encrypt `/var/lib/nanobot/env` with `sops-nix` or `agenix`.
- Add Tailscale, or configure FRITZ!Box WireGuard, for secure remote Android
  access without public port forwarding.
- Add Signal through `signal-cli` after the dashboard workflow is stable.
- Move state to a USB 3 SSD if database writes, logs, or long-term usage make
  the microSD card a bottleneck.
- Restrict dashboard access further with a VPN-only firewall policy once a
  remote-access method is selected.
