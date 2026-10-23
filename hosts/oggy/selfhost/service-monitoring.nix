{ pkgs, lib, ... }:

let
  # Probe the private Caddy address with each site's real Host and TLS identity.
  # oggy intentionally does not use its own Headscale DNS for bootstrapping.
  sites = {
    silverbullet = "/";
    t3 = "/";
    miniflux = "/healthcheck";
    syncthing = "/";
    forgejo = "/api/healthz";
    excalidash = "/";
    larapaper = "/";
    grafana = "/api/health";
    headplane = "/admin/healthz";
  };
  modules = lib.mapAttrs (name: _: {
    prober = "http";
    timeout = "10s";
    http = {
      method = "GET";
      preferred_ip_protocol = "ip4";
      fail_if_not_ssl = true;
      headers.Host = "${name}.killeik.net";
      tls_config.server_name = "${name}.killeik.net";
    };
  }) sites;
in
{
  services.prometheus.exporters.blackbox = {
    enable = true;
    listenAddress = "127.0.0.1";
    configFile = (pkgs.formats.yaml { }).generate "blackbox.yml" {
      modules = modules // {
        headscale = {
          prober = "http";
          timeout = "10s";
          http.preferred_ip_protocol = "ip4";
          http.fail_if_not_ssl = true;
        };
      };
    };
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "grafana";
      scrape_interval = "30s";
      static_configs = [ { targets = [ "192.168.1.2:3000" ]; } ];
    }
    {
      job_name = "prometheus";
      scrape_interval = "30s";
      static_configs = [ { targets = [ "127.0.0.1:9090" ]; } ];
    }
    {
      job_name = "blackbox";
      scrape_interval = "30s";
      scrape_timeout = "15s";
      metrics_path = "/probe";
      static_configs =
        lib.mapAttrsToList (name: path: {
          targets = [ "https://100.64.0.10${path}" ];
          labels = {
            service = name;
            module = name;
          };
        }) sites
        ++ [
          {
            targets = [ "https://headscale.killeik.net/health" ];
            labels = {
              service = "headscale";
              module = "headscale";
            };
          }
        ];
      relabel_configs = [
        {
          source_labels = [ "__address__" ];
          target_label = "__param_target";
        }
        {
          source_labels = [ "module" ];
          target_label = "__param_module";
        }
        {
          source_labels = [ "service" ];
          target_label = "instance";
        }
        {
          target_label = "__address__";
          replacement = "127.0.0.1:9115";
        }
      ];
    }
  ];
}
