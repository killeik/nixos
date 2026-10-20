{
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./monitoring.nix
    ./selfhost.nix
    ./codex.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
  };

  networking.hostName = "oggy";

  networking.networkmanager.enable = true;

  hardware.bluetooth.enable = true;

  time.timeZone = "Europe/Moscow";

  virtualisation.docker.enable = true;

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  users.users.killeik = {
    isNormalUser = true;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBT5yrcVE1NHFJS9qnwx+01s47mEQ+RE3IQ8dlLefkI3 killeik@onibrain-2024-07-01"
    ];
    extraGroups = [
      "wheel"
      "docker"
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    git
    usbutils
    rsync
    zip
    unzip
  ];

  system.stateVersion = "25.11";

  nix.settings = {
    trusted-users = [
      "root"
      "killeik"
    ];

    experimental-features = [
      "flakes"
      "nix-command"
    ];
  };
}
