# Hermi Raspberry Pi OpenChamber Setup

`hermi` is a headless Raspberry Pi 4 (8 GB) that runs OpenChamber and
OpenCode for persistent AI-agent work. OpenChamber is available on the home
LAN and to paired Android devices through its end-to-end encrypted Private
Relay; no router port-forward is required.

## Design

- **Host:** `hermi`
- **Hardware:** Raspberry Pi 4
- **Primary user:** `frank`
- **Agent workspace:** OpenChamber with OpenCode
- **Service user and state:** `openchamber`, `/var/lib/openchamber`
- **Web UI:** `http://hermi:3000` on the home LAN
- **Mobile access:** Android app paired with a single-use QR code
- **Remote access:** OpenChamber Private Relay, enabled only for paired devices
- **LAN identity:** fixed lease `192.168.178.71`, hostname `hermi` (Wi-Fi MAC
  `dc:a6:32:cf:0e:46`)

The firewall permits SSH (`22`) and OpenChamber (`3000`) on the LAN. Do not
configure a FRITZ!Box port-forward. Paired Android devices use the Private
Relay while away from home, and use the direct LAN connection while home.

## Configuration and Updates

`hosts/hermi/default.nix` declares the service user, OpenCode runtime,
firewall, and OpenChamber service. The service installs the version pinned by
`openchamberVersion` from npm on activation. Its mutable state and installed
node modules remain under `/var/lib/openchamber`.

Run `flake-update` from this repository to update flake inputs, desktop
OpenChamber artifacts, and hermi's pinned `@openchamber/web` version to the
latest GitHub release. A rebuild deploys that version; OpenChamber does not
self-update outside NixOS activation.

Build the SD image from the Framework:

```bash
nix build .#nixosConfigurations.hermi.config.system.build.sdImage \
  --accept-flake-config
```

For an installed Pi, deploy from the Framework:

```bash
hermi-update
```

Or rebuild from a checkout on hermi:

```bash
sudo nixos-rebuild switch --flake .#hermi --accept-flake-config
```

See the repository's existing remote deploy signing configuration if a remote
closure copy is rejected.

## Initial Setup

After the first deployment, create the UI password file. It is intentionally
outside Git and the Nix store:

```bash
sudo install -o openchamber -g openchamber -m 600 /dev/null /var/lib/openchamber/env
sudoedit /var/lib/openchamber/env
```

Set a strong password:

```text
OPENCHAMBER_UI_PASSWORD=replace-with-a-long-random-password
```

Restart the service and verify it:

```bash
sudo systemctl restart openchamber
systemctl status openchamber
journalctl -u openchamber -f
```

Open `http://hermi:3000` from a trusted LAN device and sign in with that
password. Complete the usual OpenCode provider authentication in OpenChamber.
OpenCode's configuration and credentials are stored in the OpenChamber service
user's home directory, not in this repository.

## Android Pairing

Install the APK from the [latest OpenChamber release](https://github.com/openchamber/openchamber/releases/latest).

On hermi, generate a one-time QR code that works both on the LAN and remotely:

```bash
sudo -u openchamber \
  HOME=/var/lib/openchamber \
  /var/lib/openchamber/app/node_modules/.bin/openchamber connect-url --relay --port 3000 --qr
```

In the Android app, select **Scan QR code** and scan it. The QR code expires
and can be used once. The app receives its own revocable device token, not the
UI password. Manage or revoke paired devices in **Settings -> Remote Instances
-> Connect to this server**.

The `--relay` connection falls back to OpenChamber's Private Relay away from
home. It requires only outbound traffic from hermi and is end-to-end encrypted.
Do not replace it with a public tunnel or router port-forward.

## Nanobot Migration

This configuration removes the `nanobot` and `nanobot-serve` units and closes
ports `9119` and `8900`. The former `/var/lib/nanobot` directory is not
deleted automatically. After confirming OpenChamber works and any required
credentials or notes have been migrated, remove it manually:

```bash
sudo rm -rf /var/lib/nanobot
```

Nanobot's OpenAI-compatible API is no longer provided. Use OpenChamber and
OpenCode directly for agent work.

## Routine Operations

```bash
systemctl status openchamber
journalctl -u openchamber -f
sudo systemctl restart openchamber
```

If a paired device cannot connect remotely, check **Settings -> Remote
Instances -> OpenChamber Relay** in the server UI. Revoke and re-pair the
device if its token was removed or the one-time QR code expired.
