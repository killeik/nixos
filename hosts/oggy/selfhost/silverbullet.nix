{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  virtualisation.oci-containers.containers = {
    silverbullet = commonContainerOptions // {
      image = "ghcr.io/silverbulletmd/silverbullet:latest";
      environmentFiles = [
        "${selfhostDir}/silverbullet.env"
      ];
      volumes = [
        "${selfhostDir}/silverbullet/space:/space"
      ];
    };
  };
}
