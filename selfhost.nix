{ pkgs, ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  secretsFile = "${selfhostDir}/.env";
  slskdContainerIp = "172.19.255.254";
  # terminusEnvFile = "${selfhostDir}/terminus/.env";

  commonContainerOptions = {
    pull = "always";
    extraOptions = [
      "--network=selfhost"
    ];
  };
in
{
  environment.systemPackages = with pkgs; [
    docker
  ];

  system.activationScripts.selfhost-files = ''
    install -d -m 0755 -o killeik -g users ${selfhostDir}
    install -d -m 0755 -o killeik -g users ${selfhostDir}/caddy
    install -d -m 0755 -o killeik -g users ${selfhostDir}/downloads
    install -d -m 0755 -o killeik -g users ${selfhostDir}/lidarr/config
    install -d -m 0755 -o killeik -g users ${selfhostDir}/music
    install -d -m 0755 -o killeik -g users ${selfhostDir}/navidrome/data
    install -d -m 0755 -o killeik -g users ${selfhostDir}/prowlarr/config
    install -d -m 0755 -o killeik -g users ${selfhostDir}/qbittorrent/config
    install -d -m 0755 -o killeik -g users ${selfhostDir}/slskd
    install -d -m 0755 -o killeik -g users ${selfhostDir}/soularr
    if [ ! -e ${selfhostDir}/soularr/config.ini ]; then
      install -m 0644 -o killeik -g users ${./selfhost/soularr/config.ini} ${selfhostDir}/soularr/config.ini
    fi
    # install -d -m 0755 -o killeik -g users ${selfhostDir}/terminus
    # install -d -m 0755 -o killeik -g users ${selfhostDir}/terminus/database
    # install -d -m 0755 -o killeik -g users ${selfhostDir}/terminus/keyvalue
    # install -d -m 0755 -o killeik -g users ${selfhostDir}/terminus/uploads
    install -d -m 0755 -o 82 -g 82 ${selfhostDir}/larapaper/database
    install -d -m 0755 -o 82 -g 82 ${selfhostDir}/larapaper/generated-images
    if [ ! -e ${selfhostDir}/larapaper/database/database.sqlite ]; then
      install -m 0644 -o 82 -g 82 /dev/null ${selfhostDir}/larapaper/database/database.sqlite
    else
      chown 82:82 ${selfhostDir}/larapaper/database/database.sqlite
      chmod 0644 ${selfhostDir}/larapaper/database/database.sqlite
    fi
    install -m 0644 -o killeik -g users ${./selfhost/caddy/Caddyfile} ${selfhostDir}/caddy/Caddyfile
  '';

  systemd.services.docker-caddy.restartTriggers = [ ./selfhost/caddy/Caddyfile ];
  systemd.services.docker-network-selfhost = {
    wantedBy = [ "multi-user.target" ];
    requiredBy = [ "docker-caddy.service" ];
    before = [ "docker-caddy.service" ];
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker network inspect selfhost >/dev/null 2>&1 || docker network create selfhost
    '';
  };

  systemd.services.slskd-conntrack-guard = {
    description = "Limit outgoing Slskd connection bursts";
    after = [
      "docker.service"
      "docker-network-selfhost.service"
    ];
    requires = [
      "docker.service"
      "docker-network-selfhost.service"
    ];
    before = [ "docker-slskd.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iptables ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      iptables -N SLSKD-GUARD 2>/dev/null || true
      iptables -F SLSKD-GUARD
      iptables -C DOCKER-USER -s ${slskdContainerIp}/32 -j SLSKD-GUARD 2>/dev/null \
        || iptables -I DOCKER-USER 1 -s ${slskdContainerIp}/32 -j SLSKD-GUARD

      iptables -A SLSKD-GUARD -p tcp --syn \
        -m connlimit --connlimit-above 512 --connlimit-mask 32 \
        -j REJECT --reject-with tcp-reset
      iptables -A SLSKD-GUARD -p tcp --syn \
        -m hashlimit --hashlimit-above 25/second --hashlimit-burst 100 \
        --hashlimit-mode srcip --hashlimit-srcmask 32 --hashlimit-name slskd-new \
        -j REJECT --reject-with tcp-reset
      iptables -A SLSKD-GUARD -j RETURN
    '';
    preStop = ''
      iptables -D DOCKER-USER -s ${slskdContainerIp}/32 -j SLSKD-GUARD 2>/dev/null || true
      iptables -F SLSKD-GUARD 2>/dev/null || true
      iptables -X SLSKD-GUARD 2>/dev/null || true
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
          secretsFile
        ];
        volumes = [
          "${selfhostDir}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro"
          "caddy_data:/data"
          "caddy_config:/config"
        ];
      };

      flaresolverr = commonContainerOptions // {
        image = "ghcr.io/flaresolverr/flaresolverr:latest";
        environment = {
          LOG_LEVEL = "info";
          LOG_HTML = "false";
          CAPTCHA_SOLVER = "none";
          TZ = "Europe/Moscow";
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
          POLLING_SCHEDULER = "entry_frequency";
          BATCH_SIZE = "50";
          POLLING_FREQUENCY = "90";
        };
        environmentFiles = [
          secretsFile
        ];
      };

      miniflux-db = commonContainerOptions // {
        image = "docker.io/postgres:15";
        environment = {
          POSTGRES_USER = "miniflux";
        };
        environmentFiles = [
          secretsFile
        ];
        volumes = [
          "${selfhostDir}/miniflux-db:/var/lib/postgresql/data"
        ];
      };

      rssbridge = commonContainerOptions // {
        image = "docker.io/rssbridge/rss-bridge:latest";
      };

      silverbullet = commonContainerOptions // {
        image = "ghcr.io/silverbulletmd/silverbullet:latest";
        environmentFiles = [
          secretsFile
        ];
        volumes = [
          "${selfhostDir}/silverbullet/space:/space"
        ];
      };

      forgejo = commonContainerOptions // {
        image = "codeberg.org/forgejo/forgejo:13";
        environment = {
          USER_UID = "1001";
          USER_GID = "1001";
        };
        ports = [
          "222:22"
        ];
        volumes = [
          "${selfhostDir}/forgejo:/data"
          "/etc/timezone:/etc/timezone:ro"
          "/etc/localtime:/etc/localtime:ro"
        ];
      };

      # terminus-web = commonContainerOptions // {
      #   image = "ghcr.io/usetrmnl/terminus:latest";
      #   dependsOn = [
      #     "terminus-db"
      #     "terminus-keyvalue"
      #   ];
      #   environment = {
      #     HANAMI_PORT = "2300";
      #     API_URI = "https://terminus.lan";
      #     APP_SETUP = "true";
      #   };
      #   environmentFiles = [
      #     terminusEnvFile
      #   ];
      #   ports = [
      #     "2300:2300"
      #   ];
      #   volumes = [
      #     "${selfhostDir}/terminus/uploads:/app/public/uploads"
      #   ];
      # };

      # terminus-worker = commonContainerOptions // {
      #   image = "ghcr.io/usetrmnl/terminus:latest";
      #   dependsOn = [ "terminus-web" ];
      #   cmd = [
      #     "bundle"
      #     "exec"
      #     "sidekiq"
      #     "-r"
      #     "./config/sidekiq.rb"
      #   ];
      #   environment = {
      #     HANAMI_PORT = "2300";
      #     API_URI = "https://terminus.lan";
      #   };
      #   environmentFiles = [
      #     terminusEnvFile
      #   ];
      #   volumes = [
      #     "${selfhostDir}/terminus/uploads:/app/public/uploads"
      #   ];
      # };

      # terminus-db = commonContainerOptions // {
      #   image = "docker.io/postgres:18.4-alpine";
      #   environment = {
      #     POSTGRES_USER = "terminus";
      #     POSTGRES_DB = "terminus";
      #   };
      #   environmentFiles = [
      #     terminusEnvFile
      #   ];
      #   volumes = [
      #     "${selfhostDir}/terminus/database:/var/lib/postgresql"
      #   ];
      # };

      # terminus-keyvalue = commonContainerOptions // {
      #   image = "docker.io/valkey/valkey:9-alpine";
      #   entrypoint = "/bin/sh";
      #   cmd = [
      #     "-c"
      #     "exec valkey-server --requirepass \"$KEYVALUE_PASSWORD\" --maxmemory 512mb --maxmemory-policy noeviction --port 6379"
      #   ];
      #   environmentFiles = [
      #     terminusEnvFile
      #   ];
      #   volumes = [
      #     "${selfhostDir}/terminus/keyvalue:/data"
      #   ];
      # };

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

      lidarr = commonContainerOptions // {
        image = "lscr.io/linuxserver/lidarr:latest";
        environment = {
          PUID = "1000";
          PGID = "100";
          TZ = "Europe/Moscow";
        };
        volumes = [
          "${selfhostDir}/lidarr/config:/config"
          "${selfhostDir}/music:/music"
          "${selfhostDir}/downloads:/downloads"
        ];
      };

      navidrome = commonContainerOptions // {
        image = "docker.io/deluan/navidrome:latest";
        environment = {
          ND_LOGLEVEL = "info";
          ND_SCANSCHEDULE = "1h";
          ND_SESSIONTIMEOUT = "24h";
        };
        volumes = [
          "${selfhostDir}/navidrome/data:/data"
          "${selfhostDir}/music:/music:ro"
        ];
      };

      qbittorrent = commonContainerOptions // {
        image = "lscr.io/linuxserver/qbittorrent:latest";
        environment = {
          PUID = "1000";
          PGID = "100";
          TZ = "Europe/Moscow";
          WEBUI_PORT = "8080";
        };
        ports = [
          "6881:6881/tcp"
          "6881:6881/udp"
        ];
        volumes = [
          "${selfhostDir}/qbittorrent/config:/config"
          "${selfhostDir}/downloads:/downloads"
        ];
      };

      prowlarr = commonContainerOptions // {
        image = "lscr.io/linuxserver/prowlarr:latest";
        dependsOn = [ "flaresolverr" ];
        environment = {
          PUID = "1000";
          PGID = "100";
          TZ = "Europe/Moscow";
        };
        volumes = [
          "${selfhostDir}/prowlarr/config:/config"
        ];
      };

      slskd = commonContainerOptions // {
        image = "docker.io/slskd/slskd:latest";
        user = "1000:100";
        environment = {
          SLSKD_DOWNLOAD_SLOTS = "20";
          SLSKD_DOWNLOADS_DIR = "/downloads";
          TZ = "Europe/Moscow";
          SLSKD_REMOTE_CONFIGURATION = "true";
          SLSKD_SLSK_DNET_CHILDREN = "5";
          SLSKD_SLSK_DNET_NO_CHILDREN = "true";
          SLSKD_THROTTLING_SEARCH_INCOMING_CIRCUIT_BREAKER = "100";
          SLSKD_THROTTLING_SEARCH_INCOMING_CONCURRENCY = "2";
          SLSKD_THROTTLING_SEARCH_INCOMING_RESPONSE_FILE_LIMIT = "100";
          SLSKD_UPLOAD_SLOTS = "5";
        };
        ports = [
          "50300:50300/tcp"
        ];
        extraOptions = commonContainerOptions.extraOptions ++ [
          "--ip=${slskdContainerIp}"
          "--ulimit=nofile=2048:2048"
        ];
        volumes = [
          "${selfhostDir}/slskd:/app"
          "${selfhostDir}/downloads:/downloads"
          "${selfhostDir}/music:/music:ro"
        ];
      };

      soularr = commonContainerOptions // {
        image = "docker.io/mrusse08/soularr:latest";
        user = "1000:100";
        dependsOn = [
          "lidarr"
          "slskd"
        ];
        environment = {
          TZ = "Europe/Moscow";
          SCRIPT_INTERVAL = "300";
          WEBUI_ENABLED = "true";
          WEBUI_PORT = "8265";
        };
        volumes = [
          "${selfhostDir}/downloads:/downloads"
          "${selfhostDir}/soularr:/data"
        ];
      };
    };
  };
}
