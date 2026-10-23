{ oggy, ... }:

{
  services.headscale = {
    enable = true;
    # Caddy runs in Docker and cannot reach a host loopback listener.
    address = oggy.lanAddress;
    port = 8085;
    settings = {
      server_url = "https://headscale.killeik.net";
      # Prometheus already owns 127.0.0.1:9090.
      metrics_listen_addr = "127.0.0.1:9091";
      grpc_listen_addr = "127.0.0.1:50443";
      trusted_proxies = [ oggy.dockerSubnet ];
      dns = {
        base_domain = "mesh.killeik.net";
        magic_dns = true;
        # Preserve clients' existing LAN/work DNS outside MagicDNS.
        override_local_dns = false;
      };
      derp = {
        urls = [ ];
        auto_update_enabled = false;
        server = {
          enabled = true;
          region_id = 999;
          region_code = "oggy";
          region_name = "Oggy";
          verify_clients = true;
          automatically_add_embedded_derp_region = true;
          stun_listen_addr = "0.0.0.0:3478";
        };
      };
    };
  };

  # Keep the unencrypted backend private to the existing Docker reverse proxy.
  networking.firewall.extraInputRules = ''
    iifname "br-*" ip saddr ${oggy.dockerSubnet} ip daddr ${oggy.lanAddress} tcp dport 8085 accept
  '';
  networking.firewall.allowedUDPPorts = [ 3478 ];

  services.prometheus.scrapeConfigs = [
    {
      job_name = "headscale";
      static_configs = [ { targets = [ "127.0.0.1:9091" ]; } ];
    }
  ];
}
