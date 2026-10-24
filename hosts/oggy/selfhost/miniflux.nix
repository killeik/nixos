{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  system.activationScripts.selfhost-miniflux-files = ''
    install -d -m 0755 -o killeik -g users /home/killeik/selfhost
    # docker.io/postgres:18 uses postgres 999:999 for its bind-mounted data.
    install -d -m 0700 -o 999 -g 999 /home/killeik/selfhost/miniflux-postgres
  '';

  virtualisation.oci-containers.containers = {
    reactflux = commonContainerOptions // {
      image = "docker.io/electh/reactflux@sha256:238383c04fd7d915c9539ccec0b8738bb98f15b2ebd886b1ea01a08156cf4850";
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
  };
}
