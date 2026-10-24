{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  system.activationScripts.selfhost-excalidash-files = ''
    install -d -m 0755 -o killeik -g users /home/killeik/selfhost
    install -d -m 0755 -o 1001 -g 1001 /home/killeik/selfhost/excalidash
    install -d -m 0755 -o 1001 -g 1001 /home/killeik/selfhost/excalidash/backups
    install -d -m 0755 -o 1001 -g 1001 /home/killeik/selfhost/excalidash/prisma
  '';

  virtualisation.oci-containers.containers = {
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
  };
}
