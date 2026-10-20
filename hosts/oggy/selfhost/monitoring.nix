{ pkgs, oggy, ... }:

{
  virtualisation.oci-containers.containers.caddy.ports = [ "${oggy.lanAddress}:3000:3000" ];
  networking.firewall.allowedTCPPorts = [ 3000 ];

  services.grafana = {
    enable = true;

    settings.server = {
      domain = "grafana.killeik.net";
      root_url = "https://grafana.killeik.net/";
      protocol = "socket";
      socket = "/run/grafana/grafana.sock";
      socket_mode = "0660";
    };

    settings.security.secret_key = "$__file{/var/lib/grafana/secret_key}";

    provision.datasources.settings = {
      apiVersion = 1;
      datasources = [
        {
          name = "Prometheus";
          uid = "PBFA97CFB590B2093";
          type = "prometheus";
          access = "proxy";
          url = "http://127.0.0.1:9090";
          isDefault = true;
        }
      ];
    };
  };

  systemd.services.grafana.preStart = ''
    if [ ! -s /var/lib/grafana/secret_key ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/grafana/secret_key
    fi
  '';

  # Caddy bind-mounts this directory, so its inode must survive service stops.
  systemd.services.grafana.serviceConfig.RuntimeDirectoryPreserve = "yes";

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";

    exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      enabledCollectors = [ "systemd" ];
    };

    scrapeConfigs = [
      {
        job_name = "oggy";
        static_configs = [
          {
            targets = [ "127.0.0.1:9100" ];
          }
        ];
      }
    ];
  };
}
