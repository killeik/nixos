{ ... }:

{
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  sops.gnupg.sshKeyPaths = [ ];
  sops.secrets.wireguard = {
    sopsFile = ./secrets/ingress.key.sops;
    format = "binary";
    path = "/var/lib/wireguard/ingress.key";
    owner = "root";
    group = "root";
    mode = "0600";
    restartUnits = [ "wireguard-ingress.service" ];
  };
}
