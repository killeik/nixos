{
  config,
  lib,
  pkgs,
  oggy,
  ...
}:

{
  imports = [
    ./grafana/host-alerts.nix
    ./service-monitoring.nix
    ./caddy-monitoring.nix
  ];

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

  systemd.services.grafana.preStart = lib.mkIf (!config.oggy.sops.enable) ''
    if [ ! -s /var/lib/grafana/secret_key ]; then
      umask 077
      ${pkgs.openssl}/bin/openssl rand -hex 32 > /var/lib/grafana/secret_key
    fi
  '';

  # Caddy bind-mounts this directory, so its inode must survive service stops.
  systemd.services.grafana.serviceConfig.RuntimeDirectoryPreserve = "yes";

  services.grafana.provision.dashboards.settings.providers = [
    {
      name = "home";
      folder = "Home";
      options.path = ./grafana/dashboards;
    }
  ];

  systemd.services.grafana.serviceConfig.EnvironmentFile = "/var/lib/qingping/telegram.env";

  services.grafana.provision.alerting.contactPoints.settings.contactPoints = [
    {
      orgId = 1;
      name = "qingping-telegram";
      receivers = [
        {
          uid = "qingping-telegram";
          type = "telegram";
          disableResolveMessage = false;
          settings = {
            bottoken = "$QINGPING_TELEGRAM_TOKEN";
            chatid = "$QINGPING_TELEGRAM_CHAT_ID";
            parse_mode = "None";
            disable_web_page_preview = true;
            message = ''
              {{ range .Alerts }}
              {{ if eq .Status "firing" }}{{ .Annotations.description }}{{ else }}Все, молчу.{{ end }}
              {{ .Annotations.summary }}
              {{ .DashboardURL }}
              {{ end }}
            '';
          };
        }
      ];
    }
  ];

  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";

    exporters.node = {
      enable = true;
      listenAddress = "127.0.0.1";
      enabledCollectors = [ "systemd" ];
      extraFlags = [ "--collector.textfile.directory=/var/lib/prometheus-node-exporter-text-files" ];
    };

    scrapeConfigs = [
      {
        job_name = "node";
        scrape_interval = "30s";
        static_configs = [
          {
            targets = [ "127.0.0.1:9100" ];
            labels.host = "oggy";
          }
          {
            targets = [ "sparky.home.arpa:9100" ];
            labels.host = "sparky";
          }
        ];
      }
      {
        job_name = "openwrt";
        scrape_interval = "30s";
        static_configs = [
          {
            targets = [ "${oggy.routerAddress}:9100" ];
            labels.host = "openwrt";
          }
        ];
      }
    ];
  };
}
