{ pkgs, ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  secretsFile = "${selfhostDir}/.env";

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
    install -d -m 0755 -o killeik -g users ${selfhostDir}/caddy/lan_ca
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

  virtualisation.oci-containers = {
    backend = "docker";

    containers = {
      caddy = commonContainerOptions // {
        image = "docker.io/caddy:2";
        ports = [
          "80:80"
          "443:443"
          "443:443/udp"
        ];
        volumes = [
          "${selfhostDir}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro"
          "${selfhostDir}/caddy/lan_ca:/etc/caddy/lan_ca"
          "caddy_data:/data"
          "caddy_config:/config"
        ];
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
          BASE_URL = "https://miniflux.lan/";
          HTTP_CLIENT_MAX_BODY_SIZE = "50";
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
    };
  };
}
