{ ... }:

let
  # Binary encryption preserves the complete file, including trailing newlines.
  secret = path: restartUnits: {
    sopsFile = ./secrets + "/${builtins.baseNameOf path}.sops";
    format = "binary";
    inherit path restartUnits;
    owner = "root";
    group = "root";
    mode = "0600";
  };
in
{
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.gnupg.sshKeyPaths = [ ];

  sops.secrets = {
    caddy = secret "/home/killeik/selfhost/caddy.env" [ "docker-caddy.service" ];
    miniflux = secret "/home/killeik/selfhost/miniflux.env" [ "docker-miniflux.service" ];
    # POSTGRES_PASSWORD does not rotate an initialized PostgreSQL database.
    postgres = secret "/home/killeik/selfhost/postgres.env" [ "docker-miniflux-db.service" ];
    silverbullet = secret "/home/killeik/selfhost/silverbullet.env" [ "docker-silverbullet.service" ];
    excalidash = secret "/home/killeik/selfhost/excalidash/backend.env" [
      "docker-excalidash-backend.service"
    ];
    mqtt = secret "/var/lib/qingping/mqtt-password" [
      "mosquitto.service"
      "qingping-reporting.service"
    ];
    metrics = secret "/var/lib/qingping/metrics-password" [
      "mosquitto.service"
      "qingping-exporter.service"
    ];
    telegram = secret "/var/lib/qingping/telegram.env" [ "grafana.service" ];
    link-token = secret "/var/lib/qingping/link-token" [ ];
    grafana = (secret "/var/lib/grafana/secret_key" [ "grafana.service" ]) // {
      owner = "grafana";
      group = "grafana";
    };
    wireguard = secret "/var/lib/wireguard/ingress.key" [ "wireguard-ingress.service" ];
    remote-wireguard = (secret "/var/lib/wireguard/remote-ingress.key" [ ]) // {
      sopsFile = ../morok/secrets/ingress.key.sops;
    };
    headplane = (secret "/var/lib/headplane/cookie-secret" [ "docker-headplane.service" ]) // {
      sopsFile = ./secrets/headplane-cookie.sops;
      owner = null;
      group = null;
      uid = 65532;
      gid = 65532;
    };
  };
}
