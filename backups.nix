{ pkgs, ... }:

{
  services.btrbk.instances.oggy = {
    onCalendar = "daily";
    settings = {
      timestamp_format = "long";
      snapshot_preserve_min = "latest";
      snapshot_preserve = "7d 4w 3m 0y";
      snapshot_dir = "/var/lib/btrbk/snapshots";
      volume."/".subvolume = {
        ".".snapshot_name = "root";
        "var/lib/nixos-containers/codex".snapshot_name = "codex";
      };
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/btrbk/snapshots 0750 btrbk btrbk -"
    "d /var/lib/oggy-database-backups 0700 root root -"
  ];

  systemd.services.btrbk-oggy = {
    path = [ pkgs.docker ];
    serviceConfig = {
      # Only the database preparation needs root; btrbk keeps its sudo backend.
      ExecStartPre = "+${pkgs.python3}/bin/python3 ${./scripts/backup-databases.py}";
      StateDirectoryMode = "0750";
      TimeoutStartSec = "30min";
      UMask = "0077";
    };
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
}
