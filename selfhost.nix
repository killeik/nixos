{ pkgs, ... }:

let
  selfhostDir = "/home/killeik/home/selfhost";
in
{
  environment.systemPackages = with pkgs; [
    docker-compose
  ];

  system.activationScripts.selfhost-compose = ''
    install -d -m 0755 -o killeik -g users ${selfhostDir}
    install -m 0644 -o killeik -g users ${./selfhost/compose.yaml} ${selfhostDir}/compose.yaml
  '';

  systemd.services.selfhost-compose = {
    description = "Selfhost Docker Compose stack";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" ];
    wants = [ "docker.service" "network-online.target" ];
    restartTriggers = [
      ./selfhost/compose.yaml
    ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = selfhostDir;
    };

    path = with pkgs; [
      docker
      docker-compose
    ];

    script = ''
      docker-compose up -d --remove-orphans
    '';
  };
}
