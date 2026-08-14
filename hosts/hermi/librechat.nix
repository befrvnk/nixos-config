{
  lib,
  pkgs,
  ...
}:

let
  # LibreChat is Docker-first; the official MongoDB image (mongo:8) needs AVX,
  # which the Raspberry Pi (like Apple Silicon) lacks. LibreChat's documented
  # fix for ARM is mongo:4.4.18 (the last Mongo release with arm64 images).
  # Meilisearch / RAG / admin-panel are optional; skipped for a lean test.
  composeYml = pkgs.writeText "librechat-compose.yml" ''
    services:
      api:
        container_name: librechat
        image: ghcr.io/danny-avila/librechat:latest
        restart: always
        user: "1000:1000"
        ports:
          - "3080:3080"
        environment:
          - HOST=0.0.0.0
          - PORT=3080
          - MONGO_URI=mongodb://mongodb:27017/LibreChat
        env_file:
          - /var/lib/librechat/.env
        depends_on:
          - mongodb
        volumes:
          - /var/lib/librechat/uploads:/app/uploads
          - /var/lib/librechat/logs:/app/logs
          - librechat-data:/app/data
      mongodb:
        container_name: librechat-mongodb
        image: mongo:4.4.18
        restart: always
        user: "1000:1000"
        command: [ "mongod", "--noauth" ]
        volumes:
          - /var/lib/librechat/data/mongodb:/data/db
    volumes:
      librechat-data:
  '';
in
{
  imports = [ ];
  virtualisation.docker.enable = true;

  networking.firewall.allowedTCPPorts = [ 3080 ];

  system.activationScripts."librechat-setup" = lib.stringAfter [ "users" "groups" ] ''
        mkdir -p /var/lib/librechat/data/mongodb /var/lib/librechat/uploads \
          /var/lib/librechat/logs
        chmod 0750 /var/lib/librechat
        # LibreChat's image runs as uid/gid 1000 (node) and needs to write
        # logs and uploads; mongo 4.4.18 also needs /data/db writable.
        chown -R 1000:1000 /var/lib/librechat

        # Runtime secrets live in /var/lib/librechat/.env (never in the Nix store).
        # Created once; later rebuilds leave it untouched so credentials survive.
        if [ ! -f /var/lib/librechat/.env ]; then
          openrouter_key="$(sed -n 's/^OPENROUTER_API_KEY=//p' /var/lib/nanobot/env \
            2>/dev/null | head -n1)"
          cat > /var/lib/librechat/.env <<EOF
    # LibreChat runtime secrets (generated on first activation; keep private)
    JWT_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)
    JWT_REFRESH_SECRET=$(${pkgs.openssl}/bin/openssl rand -hex 32)
    CREDS_KEY=$(${pkgs.openssl}/bin/openssl rand -hex 32)
    CREDS_IV=$(${pkgs.openssl}/bin/openssl rand -hex 32)
    OPENROUTER_MODELS=openrouter/auto
    ALLOW_REGISTRATION=true
    EOF
          if [ -n "$openrouter_key" ]; then
            echo "OPENROUTER_API_KEY=$openrouter_key" >> /var/lib/librechat/.env
          fi
          chmod 0600 /var/lib/librechat/.env
        fi
  '';

  systemd.services.librechat = {
    description = "LibreChat (Docker Compose)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    wants = [ "docker.service" ];
    path = [
      pkgs.docker
      pkgs.docker-compose
    ];
    serviceConfig = {
      Type = "simple";
      # First start pulls ~2 GB of images and may take minutes.
      TimeoutStartSec = 1200;
      Restart = "on-failure";
      RestartSec = 8;
    };
    script = ''
      cd /var/lib/librechat
      exec docker-compose -f ${composeYml} up
    '';
  };
}
