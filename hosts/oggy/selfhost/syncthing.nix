{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  virtualisation.oci-containers.containers = {
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
  };
}
