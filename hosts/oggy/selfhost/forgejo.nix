{ ... }:

let
  selfhostDir = "/home/killeik/selfhost";
  commonContainerOptions = import ./container-common.nix;
in
{
  virtualisation.oci-containers.containers = {
    forgejo = commonContainerOptions // {
      image = "codeberg.org/forgejo/forgejo:17";
      environment = {
        USER_UID = "1001";
        USER_GID = "1001";
        FORGEJO__server__ROOT_URL = "https://forgejo.killeik.net/";
        FORGEJO__server__DOMAIN = "forgejo.killeik.net";
        FORGEJO__server__SSH_DOMAIN = "forgejo.killeik.net";
        FORGEJO__server__LANDING_PAGE = "explore";
        FORGEJO__repository__DISABLE_STARS = "true";
        FORGEJO__service__SHOW_MILESTONES_DASHBOARD_PAGE = "false";
        FORGEJO__service__ENABLE_TIMETRACKING = "false";
        FORGEJO__service_0X2E_explore__DISABLE_USERS_PAGE = "true";
        FORGEJO__service_0X2E_explore__DISABLE_ORGANIZATIONS_PAGE = "true";
      };
      ports = [
        "222:22"
      ];
      volumes = [
        "${selfhostDir}/forgejo:/data"
        "/etc/localtime:/etc/localtime:ro"
      ];
    };
  };
}
