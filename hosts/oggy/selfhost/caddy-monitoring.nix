{ ... }:

{
  virtualisation.oci-containers.containers.caddy.ports = [ "127.0.0.1:9180:9180" ];

  services.prometheus.scrapeConfigs = [
    {
      job_name = "caddy";
      scrape_interval = "30s";
      static_configs = [
        {
          targets = [ "127.0.0.1:9180" ];
        }
      ];
    }
  ];
}
