{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  system.activationScripts.selfhost-larapaper-files = ''
    install -d -m 0755 -o killeik -g users /home/killeik/selfhost
    # ghcr.io/usetrmnl/larapaper uses www-data 82:82 for SQLite and images.
    install -d -m 0755 -o 82 -g 82 /home/killeik/selfhost/larapaper/database
    install -d -m 0755 -o 82 -g 82 /home/killeik/selfhost/larapaper/generated-images
    if [ ! -e /home/killeik/selfhost/larapaper/database/database.sqlite ]; then
      install -m 0644 -o 82 -g 82 /dev/null /home/killeik/selfhost/larapaper/database/database.sqlite
    else
      chown 82:82 /home/killeik/selfhost/larapaper/database/database.sqlite
      chmod 0644 /home/killeik/selfhost/larapaper/database/database.sqlite
    fi
  '';

  virtualisation.oci-containers.containers = {
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
}
