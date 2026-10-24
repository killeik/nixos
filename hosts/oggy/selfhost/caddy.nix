{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  system.activationScripts.selfhost-caddy-files = ''
    install -d -m 0755 -o killeik -g users /home/killeik/selfhost
    install -d -m 0755 -o killeik -g users /home/killeik/selfhost/caddy
    install -m 0644 -o killeik -g users ${./caddy/Caddyfile} /home/killeik/selfhost/caddy/Caddyfile
  '';

  systemd.services.docker-caddy.restartTriggers = [ ./caddy/Caddyfile ];
  systemd.services.docker-caddy.after = [ "grafana.service" ];

  virtualisation.oci-containers.containers = {
    caddy = commonContainerOptions // {
      image = "docker.io/caddybuilds/caddy-cloudflare:latest";
      ports = [
        "80:80"
        "443:443"
        "443:443/udp"
      ];
      environmentFiles = [
        "${selfhostDir}/caddy.env"
      ];
      volumes = [
        "${selfhostDir}/caddy/Caddyfile:/etc/caddy/Caddyfile:ro"
        "/run/grafana:/run/grafana:ro"
        "caddy_data:/data"
        "caddy_config:/config"
      ];
    };
  };
}
