{
  config,
  lib,
  pkgs,
  oggy,
  ...
}:

let
  selfhostDir = "/home/killeik/selfhost";

  selfhostContainerServices = lib.mapAttrsToList (_: container: "${container.serviceName}.service") (
    lib.filterAttrs (
      _: container: builtins.elem "selfhost" container.networks
    ) config.virtualisation.oci-containers.containers
  );

  # PUID/PGID and user 1000:100 below match oggy killeik:users on shared media.
  commonContainerOptions = {
    pull = "always";
    networks = [ "selfhost" ];
  };
in
{
  imports = [
    ./monitoring.nix
    ./smarthome.nix
    ./codex.nix
    ./backups.nix
    ./headscale.nix
  ];

  system.activationScripts.selfhost-files = ''
    install -d -m 0755 -o killeik -g users ${selfhostDir}
    install -d -m 0755 -o killeik -g users ${selfhostDir}/caddy
    # Excalidash backend runs as nodejs UID 1001 (primary GID 65533).
    # Owner access is required; retain the existing on-disk GID 1001.
    install -d -m 0755 -o 1001 -g 1001 ${selfhostDir}/excalidash
    install -d -m 0755 -o 1001 -g 1001 ${selfhostDir}/excalidash/backups
    install -d -m 0755 -o 1001 -g 1001 ${selfhostDir}/excalidash/prisma
    ${lib.optionalString (!config.oggy.sops.enable) ''
      if [ ! -e ${selfhostDir}/excalidash/backend.env ]; then
        install -m 0600 -o root -g root /dev/null ${selfhostDir}/excalidash/backend.env
        printf 'API_KEY_HASH_PEPPER=%s\n' "$(${pkgs.openssl}/bin/openssl rand -hex 32)" \
          > ${selfhostDir}/excalidash/backend.env
      fi
    ''}
    # docker.io/postgres:18 uses postgres 999:999 for its bind-mounted data.
    install -d -m 0700 -o 999 -g 999 ${selfhostDir}/miniflux-postgres
    # ghcr.io/usetrmnl/larapaper uses www-data 82:82 for SQLite and images.
    install -d -m 0755 -o 82 -g 82 ${selfhostDir}/larapaper/database
    install -d -m 0755 -o 82 -g 82 ${selfhostDir}/larapaper/generated-images
    if [ ! -e ${selfhostDir}/larapaper/database/database.sqlite ]; then
      install -m 0644 -o 82 -g 82 /dev/null ${selfhostDir}/larapaper/database/database.sqlite
    else
      chown 82:82 ${selfhostDir}/larapaper/database/database.sqlite
      chmod 0644 ${selfhostDir}/larapaper/database/database.sqlite
    fi
    install -m 0644 -o killeik -g users ${./caddy/Caddyfile} ${selfhostDir}/caddy/Caddyfile
  '';

  systemd.services.docker-caddy.restartTriggers = [ ./caddy/Caddyfile ];
  systemd.services.docker-caddy.after = [ "grafana.service" ];
  systemd.services.docker-network-selfhost = {
    wantedBy = [ "multi-user.target" ];
    requiredBy = selfhostContainerServices;
    before = selfhostContainerServices;
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    partOf = [ "docker.service" ];
    path = [ config.virtualisation.docker.package ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker network inspect selfhost >/dev/null 2>&1 || docker network create --subnet=${oggy.dockerSubnet} selfhost
      # Never recreate an existing network: running containers may still use it.
      subnet=$(docker network inspect --format '{{range .IPAM.Config}}{{println .Subnet}}{{end}}' selfhost)
      if [ "$subnet" != "${oggy.dockerSubnet}" ]; then
        echo "selfhost network subnet is $subnet; expected ${oggy.dockerSubnet}. Refusing to recreate it." >&2
        exit 1
      fi
    '';
  };

  virtualisation.oci-containers = {
    backend = "docker";

    containers = {
      caddy = commonContainerOptions // {
        image = "docker.io/caddybuilds/caddy-cloudflare:latest";
        ports = [
          "80:80"
          "443:443"
          "443:443/udp"
        ];
        environmentFiles = [
          "${selfhostDir}/caddy.env"
        ];
        volumes = [
          "${selfhostDir}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro"
          "/run/grafana:/run/grafana:ro"
          "caddy_data:/data"
          "caddy_config:/config"
        ];
      };

      excalidash-backend = commonContainerOptions // {
        image = "docker.io/zimengxiong/excalidash-backend:latest";
        environmentFiles = [
          "${selfhostDir}/excalidash/backend.env"
        ];
        environment = {
          AUTH_MODE = "local";
          BACKUP_DIR = "/app/backups";
          BACKUP_RETENTION_DAYS = "14";
          BACKUP_SCHEDULE = "0 0 4 * * *";
          DATABASE_PROVIDER = "sqlite";
          DATABASE_URL = "file:/app/prisma/dev.db";
          FRONTEND_URL = "https://excalidash.killeik.net";
          NODE_ENV = "production";
          PORT = "8000";
          TRUST_PROXY = "2";
        };
        volumes = [
          "${selfhostDir}/excalidash/backups:/app/backups"
          "${selfhostDir}/excalidash/prisma:/app/prisma"
        ];
      };

      excalidash-frontend = commonContainerOptions // {
        image = "docker.io/zimengxiong/excalidash-frontend:latest";
        dependsOn = [ "excalidash-backend" ];
        environment = {
          BACKEND_URL = "excalidash-backend:8000";
        };
      };

      syncthing = commonContainerOptions // {
        image = "docker.io/syncthing/syncthing:latest";
        hostname = "my-syncthing";
        environment = {
          PUID = "1000";
          PGID = "100";
        };
        ports = [
          "22000:22000/tcp"
          "22000:22000/udp"
          "21027:21027/udp"
        ];
        volumes = [
          "${selfhostDir}/syncthing:/var/syncthing"
        ];
      };

      miniflux = commonContainerOptions // {
        image = "docker.io/miniflux/miniflux:latest";
        dependsOn = [ "miniflux-db" ];
        environment = {
          RUN_MIGRATIONS = "1";
          FETCH_YOUTUBE_WATCH_TIME = "1";
          BASE_URL = "https://miniflux.killeik.net/";
          HTTP_CLIENT_MAX_BODY_SIZE = "50";
          POLLING_LIMIT_PER_HOST = "30";
          POLLING_PARSING_ERROR_LIMIT = "0";
          POLLING_SCHEDULER = "entry_frequency";
          BATCH_SIZE = "50";
          POLLING_FREQUENCY = "90";
        };
        environmentFiles = [
          "${selfhostDir}/miniflux.env"
        ];
      };

      miniflux-db = commonContainerOptions // {
        image = "docker.io/postgres:18";
        environment = {
          POSTGRES_USER = "miniflux";
        };
        environmentFiles = [
          "${selfhostDir}/postgres.env"
        ];
        volumes = [
          "${selfhostDir}/miniflux-postgres:/var/lib/postgresql"
        ];
      };

      rssbridge = commonContainerOptions // {
        image = "docker.io/rssbridge/rss-bridge:latest";
      };

      silverbullet = commonContainerOptions // {
        image = "ghcr.io/silverbulletmd/silverbullet:latest";
        environmentFiles = [
          "${selfhostDir}/silverbullet.env"
        ];
        volumes = [
          "${selfhostDir}/silverbullet/space:/space"
        ];
      };

      forgejo = commonContainerOptions // {
        image = "codeberg.org/forgejo/forgejo:17";
        environment = {
          USER_UID = "1001";
          USER_GID = "1001";
          FORGEJO__server__ROOT_URL = "https://forgejo.killeik.net/";
          FORGEJO__server__DOMAIN = "forgejo.killeik.net";
          FORGEJO__server__SSH_DOMAIN = "forgejo.killeik.net";
          FORGEJO__server__LANDING_PAGE = "explore";
          FORGEJO__repository__DISABLE_STARS = "true";
          FORGEJO__service__SHOW_MILESTONES_DASHBOARD_PAGE = "false";
          FORGEJO__service__ENABLE_TIMETRACKING = "false";
          FORGEJO__service_0X2E_explore__DISABLE_USERS_PAGE = "true";
          FORGEJO__service_0X2E_explore__DISABLE_ORGANIZATIONS_PAGE = "true";
        };
        ports = [
          "222:22"
        ];
        volumes = [
          "${selfhostDir}/forgejo:/data"
          "/etc/localtime:/etc/localtime:ro"
        ];
      };

      larapaper = commonContainerOptions // {
        image = "ghcr.io/usetrmnl/larapaper:latest";
        environment = {
          DB_CONNECTION = "sqlite";
          PHP_OPCACHE_ENABLE = "1";
          TRMNL_PROXY_REFRESH_MINUTES = "15";
          DB_DATABASE = "/var/www/html/database/storage/database.sqlite";
        };
        ports = [
          "4567:8080"
        ];
        volumes = [
          "${selfhostDir}/larapaper/database:/var/www/html/database/storage"
          "${selfhostDir}/larapaper/generated-images:/var/www/html/storage/app/public/images/generated"
        ];
      };

    };
  };
}
