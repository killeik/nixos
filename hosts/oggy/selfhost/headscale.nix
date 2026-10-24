{ pkgs, ... }:

{
  networking.wireguard.interfaces.ingress = {
    ips = [ "10.76.0.2/32" ];
    privateKeyFile = "/var/lib/wireguard/ingress.key";
    peers = [
      {
        publicKey = "LOrveBGlyOuHjfHkZQxCNzBP645JgK3KkuwtlQdAHWM=";
        allowedIPs = [ "10.76.0.1/32" ];
        endpoint = "194.67.122.181:51871";
        persistentKeepalive = 25;
      }
    ];
  };

  services.tailscale = {
    enable = true;
    # The control server must retain its ordinary DNS/bootstrap connectivity.
    extraSetFlags = [ "--accept-dns=false" ];
  };

  services.headscale = {
    enable = true;
    address = "10.76.0.2";
    port = 8085;
    settings = {
      server_url = "https://headscale.killeik.net";
      # Prometheus already owns 127.0.0.1:9090.
      metrics_listen_addr = "127.0.0.1:9091";
      grpc_listen_addr = "127.0.0.1:50443";
      trusted_proxies = [ "10.76.0.1/32" ];
      dns = {
        base_domain = "mesh.killeik.net";
        magic_dns = true;
        # Preserve clients' existing LAN/work DNS outside MagicDNS.
        override_local_dns = false;
        # These private answers preserve the existing Caddy hostnames and TLS.
        extra_records =
          map
            (name: {
              inherit name;
              type = "A";
              value = "100.64.0.10";
            })
            [
              "silverbullet.killeik.net"
              "t3.killeik.net"
              "miniflux.killeik.net"
              "syncthing.killeik.net"
              "forgejo.killeik.net"
              "excalidash.killeik.net"
              "larapaper.killeik.net"
              "grafana.killeik.net"
            ];
      };
      derp = {
        urls = [ ];
        auto_update_enabled = false;
        server.enabled = false;
        paths = [
          (pkgs.writeText "selfhost-derp.yaml" ''
            regions:
              999:
                regionid: 999
                regioncode: selfhost
                regionname: Selfhost
                nodes:
                  - name: selfhost
                    regionid: 999
                    hostname: derp.killeik.net
                    ipv4: 194.67.122.181
                    ipv6: none
                    stunport: 3478
                    derpport: 443
                    canport80: true
          '')
        ];
      };
    };
  };

  systemd.services.headscale = {
    requires = [ "wireguard-ingress.service" ];
    after = [ "wireguard-ingress.service" ];
  };
  # The gateway may reach Headscale, not arbitrary services on oggy or the LAN.
  networking.firewall.interfaces.ingress.allowedTCPPorts = [ 8085 ];
  # Global firewall allows also apply to VPN interfaces; restrict this peer first.
  networking.nftables.tables.ingress-guard = {
    family = "inet";
    content = ''
      chain input {
        type filter hook input priority filter - 10; policy accept;
        iifname "ingress" ct state established,related accept
        iifname "ingress" tcp dport 8085 accept
        iifname "ingress" drop
      }
      chain forward {
        type filter hook forward priority filter - 10; policy accept;
        iifname "ingress" drop
      }
    '';
  };

  services.prometheus.scrapeConfigs = [
    {
      job_name = "headscale";
      static_configs = [ { targets = [ "127.0.0.1:9091" ]; } ];
    }
  ];
}
