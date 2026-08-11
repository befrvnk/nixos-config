# Hermi Raspberry Pi Hermes Setup

This document describes building, provisioning, and operating `hermi`: a
headless Raspberry Pi 4 (8 GB) running Hermes Agent with OpenRouter.

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
- **Agent:** native Hermes NixOS service
- **State directory:** `/var/lib/hermes`
- **Dashboard:** `http://hermi:9119` on the home LAN, protected with basic authentication
- **Model provider:** OpenRouter

Do not configure a FRITZ!Box port-forward for SSH or the dashboard. The
initial setup is intended for the trusted home LAN only. For access away from
home, add Tailscale or use the FRITZ!Box WireGuard VPN later.

## Repository Layout

The relevant configuration is:

- `hosts/hermi/default.nix` — Pi hardware, SSH, networking, Hermes, and dashboard
- `flake.nix` — `nixosConfigurations.hermi` and the upstream Hermes flake input
- `hosts/framework/default.nix` — enables AArch64 emulation needed to build the image

The Pi configuration imports the NixOS hardware profile for the Raspberry Pi
4 and the generic AArch64 SD-card image module.

## Prerequisites

Before building, have:

- the Framework running NixOS and a current checkout of this repository;
- a Raspberry Pi 4, power supply, microSD card, and Ethernet cable;
- Ethernet connected to the FRITZ!Box for first boot;
- the `hermi` SSH key available through the 1Password SSH agent on the Framework;
- an OpenRouter API key, but do not add it to Git or a Nix expression.

Confirm that the 1Password SSH agent offers the `hermi` public key:

```bash
ssh-add -L
```

The output should contain the dedicated `ssh-ed25519` public key configured in
`hosts/hermi/default.nix`.

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
  --accept-flake-config
```

The first build can be slow. Nix downloads available target packages from
binary caches and uses emulation only where needed.

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
ssh-add -L
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

## Configure Hermes Secrets and Dashboard Authentication

The image intentionally starts without provider or dashboard credentials. Put
them in `/var/lib/hermes/env`, which is loaded directly by both the Hermes
gateway and dashboard services.

Generate a dashboard session secret:

```bash
openssl rand -base64 32
```

Create the environment file. Substitute actual values; keep the OpenRouter key
and password private:

```bash
sudo tee /var/lib/hermes/env >/dev/null <<'EOF'
OPENROUTER_API_KEY=replace-with-openrouter-key
HERMES_DASHBOARD_BASIC_AUTH_USERNAME=frank
HERMES_DASHBOARD_BASIC_AUTH_PASSWORD=replace-with-a-long-unique-password
HERMES_DASHBOARD_BASIC_AUTH_SECRET=replace-with-the-generated-secret
EOF
sudo chown hermes:hermes /var/lib/hermes/env
sudo chmod 0600 /var/lib/hermes/env
```

Never put these values in `hosts/hermi/default.nix`, any other Nix expression,
or a committed file. Nix expressions become readable through the Nix store.

Restart the gateway and start the dashboard:

```bash
sudo systemctl restart hermes-agent
sudo systemctl start hermes-dashboard
```

Check status and logs if needed:

```bash
systemctl status hermes-agent hermes-dashboard
journalctl -u hermes-agent -u hermes-dashboard -f
```

## Use the Dashboard from Android

Connect the Android device to the same home Wi-Fi, then browse to:

```text
http://hermi:9119
```

If the name does not resolve, use the Pi's current LAN address instead:

```text
http://<pi-ip-address>:9119
```

Sign in using the dashboard credentials from `/var/lib/hermes/env`. Add the
page to the browser's home screen for an app-like launcher.

The dashboard is configured to listen on port `9119`, which is open in the Pi
firewall. It remains inaccessible from the public Internet unless a router
port-forward is deliberately created; do not create one.

## Choose a Model

The initial Nix configuration deliberately does not pin a model. After signing
in to the dashboard, select a model available through OpenRouter. This avoids
committing a provider-specific model choice and allows experimentation.

## Routine Operations

### Service status and logs

```bash
systemctl status hermes-agent hermes-dashboard
journalctl -u hermes-agent -f
journalctl -u hermes-dashboard -f
```

### Restart services after changing `/var/lib/hermes/env`

```bash
sudo systemctl restart hermes-agent hermes-dashboard
```

### Update the Pi configuration

Make and commit changes in this repository, then build a new SD image from the
Framework for a fresh installation. For an already-installed Pi, use the
repository checkout on the Pi and run:

```bash
sudo nixos-rebuild switch --flake .#hermi --accept-flake-config
```

The native Hermes NixOS module is declarative. Change its Nix settings and
rebuild rather than using `hermes setup` or `hermes gateway install`.

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
  --use-remote-sudo \
  --accept-flake-config
```

This is different from a remote *builder*: the Framework performs the build,
copies its result to the target Pi, then activates it remotely. It is the
recommended remote deployment workflow until a separate native AArch64 builder
is available.

## Future Improvements

- Encrypt `/var/lib/hermes/env` with `sops-nix` or `agenix`.
- Add Tailscale, or configure FRITZ!Box WireGuard, for secure remote Android
  access without public port forwarding.
- Add Signal through `signal-cli` after the dashboard workflow is stable.
- Move state to a USB 3 SSD if database writes, logs, or long-term usage make
  the microSD card a bottleneck.
- Restrict dashboard access further with a VPN-only firewall policy once a
  remote-access method is selected.
