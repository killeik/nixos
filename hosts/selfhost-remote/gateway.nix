{ lib, pkgs, ... }:

{
  networking.wireguard.interfaces.ingress = {
    ips = [ "10.76.0.1/32" ];
    listenPort = 51871;
    privateKeyFile = "/var/lib/wireguard/ingress.key";
    peers = [
      {
        publicKey = "YUjfa714XdC30bn8wCUcZx7EBF8IiEzFJq5BCx6T5Ho=";
        allowedIPs = [ "10.76.0.2/32" ];
      }
    ];
  };
  networking.firewall.allowedTCPPorts = [
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [ 51871 ];

  security.acme.acceptTerms = true;
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=headscale:10m rate=10r/s;
    '';
    virtualHosts."headscale.killeik.net" = {
      enableACME = true;
      forceSSL = true;
      locations."= /verify".return = "404";
      locations."/" = {
        proxyPass = "http://10.76.0.2:8085";
        proxyWebsockets = true;
        extraConfig = ''
          # Headscale prioritizes this header over X-Forwarded-For.
          proxy_set_header True-Client-IP $remote_addr;
          proxy_buffering off;
          proxy_read_timeout 3600s;
          proxy_send_timeout 3600s;
          limit_req zone=headscale burst=30 nodelay;
          limit_req_status 429;
        '';
      };
    };
    virtualHosts."derp.killeik.net".enableACME = true;
  };

  # Admission stays inside WireGuard and fails closed if oggy is unavailable.
  systemd.services.tailscale-derper.serviceConfig.ExecStart = lib.mkForce (
    "${pkgs.tailscale.derper}/bin/derper"
    + " -a :8010 -c /var/lib/derper/derper.key"
    + " -hostname=derp.killeik.net -stun-port=3478 -http-port=-1"
    + " -verify-client-url=http://10.76.0.2:8085/verify"
    + " -verify-client-url-fail-open=false"
  );

  services.tailscale.derper = {
    enable = true;
    domain = "derp.killeik.net";
  };
}
