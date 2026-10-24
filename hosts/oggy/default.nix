{
  pkgs,
  oggy,
  ...
}:

{
  imports = [
    ./hardware.nix
    ../../modules/nixos/base.nix
    ./selfhost
    ./secrets.nix
  ];

  # Shared host parameters are module arguments, not separately imported values.
  _module.args.oggy = {
    lanAddress = "192.168.1.2";
    dnsAddress = "192.168.1.1";
    routerAddress = "192.168.1.1";
    tailnetAddress = "100.64.0.10";
    headscaleAddress = "10.76.0.2";
    externalInterface = "enp0s20f0u3u4";
    dockerSubnet = "172.19.0.0/16";
    qingpingDeviceId = "ccb5d1327498";
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
  };

  networking.hostName = "oggy";

  networking.networkmanager.enable = true;

  networking.nat = {
    enable = true;
    externalInterface = oggy.externalInterface;
  };

  hardware.bluetooth.enable = true;

  networking.nftables = {
    enable = true;
    # Docker owns its iptables-nft tables; reload only our declarative tables.
    flushRuleset = false;
  };
  networking.firewall = {
    filterForward = true;
    extraForwardRules = ''
      iifname { "docker0", "br-*" } accept
    '';
  };
  virtualisation.docker = {
    enable = true;
    # Keep the stable backend. The NixOS nftables firewall owns the forward policy.
    daemon.settings = {
      firewall-backend = "iptables";
      ip-forward-no-drop = true;
    };
  };
  systemd.services.docker = {
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh.settings.PermitRootLogin = "no";

  users.users.killeik = {
    isNormalUser = true;
    uid = 1000;
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
  nix.settings.trusted-users = [
    "root"
    "killeik"
  ];
}
