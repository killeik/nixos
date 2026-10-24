{
  config,
  pkgs,
  oggy,
  ...
}:

let
  settings = (pkgs.formats.yaml { }).generate "headplane.yaml" {
    server = {
      host = "0.0.0.0";
      port = 3000;
      base_url = "https://headplane.killeik.net";
      cookie_secure = true;
      cookie_secret_path = "/etc/headplane/cookie-secret";
      data_path = "/var/lib/headplane";
    };
    headscale = {
      url = "http://${oggy.headscaleAddress}:8085";
      public_url = "https://headscale.killeik.net";
      config_path = "/etc/headscale/config.yaml";
      config_strict = false;
    };
    # Nix owns the read-only config; no process, Docker socket or agent integration.
    integration.proc.enabled = false;
  };
in
{
  # Distroless nonroot UID, isolated from Headscale's Unix identity.
  systemd.tmpfiles.rules = [ "d /var/lib/headplane 0700 65532 65532 -" ];
  virtualisation.oci-containers.containers.headplane = {
    image = "ghcr.io/tale/headplane:0.8.2";
    pull = "always";
    networks = [ "selfhost" ];
    user = "65532:65532";
    volumes = [
      "${settings}:/etc/headplane/config.yaml:ro"
      "${config.services.headscale.configFile}:/etc/headscale/config.yaml:ro"
      "/var/lib/headplane:/var/lib/headplane"
      "${config.sops.secrets.headplane.path}:/etc/headplane/cookie-secret:ro"
    ];
    extraOptions = [
      "--cap-drop=ALL"
      "--security-opt=no-new-privileges:true"
      "--read-only"
      "--tmpfs=/tmp:rw,nosuid,nodev,noexec"
    ];
  };

  # The panel reaches the native API through the host, authenticated by API key.
  networking.firewall.extraInputRules = ''
    iifname "br-*" ip saddr ${oggy.dockerSubnet} ip daddr ${oggy.headscaleAddress} tcp dport 8085 accept
  '';
}
