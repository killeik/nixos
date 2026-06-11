{ pkgs, ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  secretsFile = "${selfhostDir}/.env";

  commonContainerOptions = {
    pull = "always";
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
        extraOptions = [
          "--add-host=host.docker.internal:host-gateway"
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
          PUID = "1001";
          PGID = "1001";
        };
        ports = [
          "127.0.0.1:8384:8384"
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
        ports = [
          "127.0.0.1:8080:8080"
        ];
        extraOptions = [
          "--add-host=host.docker.internal:host-gateway"
        ];
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
        ports = [
          "127.0.0.1:5432:5432"
        ];
        volumes = [
          "${selfhostDir}/miniflux-db:/var/lib/postgresql/data"
        ];
      };

      rssbridge = commonContainerOptions // {
        image = "docker.io/rssbridge/rss-bridge:latest";
        ports = [
          "127.0.0.1:8081:80"
        ];
      };

      silverbullet = commonContainerOptions // {
        image = "ghcr.io/silverbulletmd/silverbullet:latest";
        ports = [
          "127.0.0.1:3001:3000"
        ];
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
          "127.0.0.1:3000:3000"
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
