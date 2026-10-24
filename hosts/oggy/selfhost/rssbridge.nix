{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  virtualisation.oci-containers.containers = {
    rssbridge = commonContainerOptions // {
      image = "docker.io/rssbridge/rss-bridge:latest";
    };
  };
}
