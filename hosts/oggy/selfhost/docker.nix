{
  config,
  lib,
  oggy,
  ...
}:

let
  selfhostContainerServices = lib.mapAttrsToList (_: container: "${container.serviceName}.service") (
    lib.filterAttrs (
      _: container: builtins.elem "selfhost" container.networks
    ) config.virtualisation.oci-containers.containers
  );

in
{
  virtualisation.oci-containers.backend = "docker";

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
}
