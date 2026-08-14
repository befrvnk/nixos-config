{
  inputs,
  lib,
  nixos-raspberrypi,
  pkgs,
  ...
}:

let
  nanobotVersion = "0.3.0";
in
{
  imports = [
    ./librechat.nix
    nixos-raspberrypi.nixosModules.raspberry-pi-4.base
    nixos-raspberrypi.nixosModules.sd-image
  ];

  # The sd-image profile enables ZFS support via profiles/base.nix, but hermi is
  # ext4-only. Disable it to silence the boot.zfs.forceImportRoot eval warning and
  # avoid pulling the zfs kernel module, services, and package into the image.
  boot.supportedFilesystems.zfs = lib.mkForce false;

  networking = {
    hostName = "hermi";
    networkmanager.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [
        22
        8900
        9119
      ];
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      KbdInteractiveAuthentication = false;
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      # Accept TERM from the Framework (SetEnv in home-manager/shared/ssh.nix)
      # so Ghostty's xterm-ghostty value never reaches the Pi's ncurses.
      AcceptEnv = [ "TERM" ];
    };
  };

  users = {
    users = {
      frank = {
        isNormalUser = true;
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINORbEqnNt1PuKmKZn0BW/lmbAvy8L6+q1V9PP9W4vQg"
        ];
      };

      # Nanobot personal AI agent (WebUI on :9119)
      # Replaces the former hermes-agent gateway. The runtime is a pinned PyPI
      # venv (nanobot-ai is not packaged in nixpkgs); the venv is created at
      # first activation and reused afterwards. Provider secrets come from
      # /var/lib/nanobot/env (see docs/hermi-raspberry-pi-setup.md).
      nanobot = {
        isSystemUser = true;
        group = "nanobot";
        home = "/var/lib/nanobot";
        createHome = true;
      };
    };
    groups.nanobot = { };
  };

  # The image has no password hash for frank. SSH public-key authentication is
  # therefore the initial administrative credential; require a password only
  # after one has been configured on the Pi.
  security.sudo.wheelNeedsPassword = false;

  system.activationScripts."nanobot-setup" = lib.stringAfter [ "users" "groups" ] ''
    mkdir -p /var/lib/nanobot /var/lib/nanobot/.nanobot
    chown nanobot:nanobot /var/lib/nanobot /var/lib/nanobot/.nanobot
    chmod 0750 /var/lib/nanobot

    # One-time venv bootstrap (downloads from PyPI on first activation).
    if [ ! -x /var/lib/nanobot/venv/bin/nanobot ]; then
      echo "Creating nanobot ${nanobotVersion} venv (first activation; downloads PyPI)..."
      ${pkgs.uv}/bin/uv venv --python "${pkgs.python3}" /var/lib/nanobot/venv
      ${pkgs.uv}/bin/uv pip install --python /var/lib/nanobot/venv/bin/python "nanobot-ai[api]==${nanobotVersion}"
    fi

    # Optional secrets from /var/lib/nanobot/env (nanobot user's own file).
    ws_token="$(sed -n 's/^NANOBOT_WS_TOKEN=//p' /var/lib/nanobot/env 2>/dev/null | head -n1)"
    api_key="$(sed -n 's/^NANOBOT_API_KEY=//p' /var/lib/nanobot/env 2>/dev/null | head -n1)"
    openrouter_key="$(sed -n 's/^OPENROUTER_API_KEY=//p' /var/lib/nanobot/env 2>/dev/null | head -n1)"

    # Seed a minimal config on first run, then only upsert so the model and
    # provider state nanobot itself wrote (onboarding/WebUI) survives.
    if [ ! -f /var/lib/nanobot/.nanobot/config.json ]; then
      ${pkgs.jq}/bin/jq -n \
        '{channels:{websocket:{enabled:true,host:"127.0.0.1",port:9119}}}' \
        > /var/lib/nanobot/.nanobot/config.json
    fi

    # WebUI: LAN entry + browser password on :9119 when a token is set.
    if [ -n "$ws_token" ]; then
      ${pkgs.jq}/bin/jq --arg t "$ws_token" \
        '.channels.websocket = ((.channels.websocket // {enabled:true}) | .host="0.0.0.0" | .port=9119 | .tokenIssueSecret=$t | .websocketRequiresToken=true)' \
        /var/lib/nanobot/.nanobot/config.json > /var/lib/nanobot/.nanobot/config.json.tmp
      mv /var/lib/nanobot/.nanobot/config.json.tmp /var/lib/nanobot/.nanobot/config.json
    fi

    # OpenAI-compatible API on :8900 (Conduit/OpenAI SDK clients).
    if [ -n "$api_key" ]; then
      ${pkgs.jq}/bin/jq --arg k "$api_key" \
        '.api = {host:"0.0.0.0",port:8900,apiKey:$k}' \
        /var/lib/nanobot/.nanobot/config.json > /var/lib/nanobot/.nanobot/config.json.tmp
      mv /var/lib/nanobot/.nanobot/config.json.tmp /var/lib/nanobot/.nanobot/config.json
    fi

    # OpenRouter entry so a headless first start passes the provider preflight.
    # extra_body routes every request to the highest-throughput provider
    # (evidence/proof: https://openrouter.ai/docs/guides/routing/provider-selection)
    if [ -n "$openrouter_key" ]; then
      ${pkgs.jq}/bin/jq --arg k "$openrouter_key" \
        '.providers.openrouter = {api_base:"https://openrouter.ai/api/v1",api_key:$k,extra_body:{provider:{sort:"throughput",allow_fallbacks:true}}}' \
        /var/lib/nanobot/.nanobot/config.json > /var/lib/nanobot/.nanobot/config.json.tmp
      mv /var/lib/nanobot/.nanobot/config.json.tmp /var/lib/nanobot/.nanobot/config.json
    fi

    chown nanobot:nanobot /var/lib/nanobot/.nanobot/config.json
    chmod 0600 /var/lib/nanobot/.nanobot/config.json
  '';

  systemd.services.nanobot = {
    description = "Nanobot personal AI agent";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    environment = {
      HOME = "/var/lib/nanobot";
      # NixOS has no /bin/bash; give the exec tool a real shell + tools.
      PATH = lib.mkForce "/run/current-system/sw/bin";
    };
    serviceConfig = {
      User = "nanobot";
      Group = "nanobot";
      WorkingDirectory = "/var/lib/nanobot";
      EnvironmentFile = "-/var/lib/nanobot/env";
      ExecStart = "/var/lib/nanobot/venv/bin/nanobot webui --yes --no-open";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  systemd.services.nanobot-serve = {
    description = "Nanobot OpenAI-compatible API server";
    wantedBy = [ "multi-user.target" ];
    after = [ "nanobot.service" ];
    environment = {
      HOME = "/var/lib/nanobot";
      PATH = lib.mkForce "/run/current-system/sw/bin";
    };
    serviceConfig = {
      User = "nanobot";
      Group = "nanobot";
      WorkingDirectory = "/var/lib/nanobot";
      EnvironmentFile = "-/var/lib/nanobot/env";
      ExecStart = "/var/lib/nanobot/venv/bin/nanobot serve";
      Restart = "on-failure";
      RestartSec = 5;
      UMask = "0077";
    };
  };

  environment.systemPackages = with pkgs; [
    bash
    curl
    git
    neovim
  ];

  system.stateVersion = "25.05";
}
