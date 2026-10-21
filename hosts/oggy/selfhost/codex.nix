{
  config,
  pkgs,
  oggy,
  ...
}:
{
  # The persistent root is a Btrfs subvolume, prepared before first activation.
  containers.codex = {
    autoStart = true;
    ephemeral = false;
    privateUsers = "pick";
    privateNetwork = true;
    hostAddress = "10.231.40.1";
    localAddress = "10.231.40.2";
    config =
      { pkgs, ... }:
      {
        system.stateVersion = "25.11";
        networking.hostName = "codex";
        environment.etc."machine-info".text = ''
          PRETTY_HOSTNAME="oggy"
        '';
        networking.useHostResolvConf = false;
        networking.nameservers = [ oggy.dnsAddress ];
        networking.enableIPv6 = false;
        services.openssh = {
          enable = true;
          settings = {
            PasswordAuthentication = false;
            KbdInteractiveAuthentication = false;
            PermitRootLogin = "no";
          };
        };
        users.users.codex = {
          isNormalUser = true;
          uid = 1000;
          linger = true;
          openssh.authorizedKeys.keys = config.users.users.killeik.openssh.authorizedKeys.keys;
        };
        environment.systemPackages = with pkgs; [
          git
          ripgrep
          tmux
          curl
          jq
          nodejs
          python3
          uv
          gcc
          gnumake
          pkg-config
        ];
        programs.nix-ld.enable = true;
        environment.localBinInPath = true;
        # The official CLI owns the user unit and runtime so its updater can switch versions.
        systemd.user.services.t3code = {
          overrideStrategy = "asDropin";
          serviceConfig = {
            Environment = [
              "PATH=/home/codex/.local/bin:/run/current-system/sw/bin"
              "T3CODE_HOST=0.0.0.0"
              "T3CODE_PORT=3773"
            ];
            UMask = "0077";
          };
        };
        networking.firewall.allowedTCPPorts = [ 3773 ];
        nix.settings.experimental-features = [
          "nix-command"
          "flakes"
        ];
        services.journald.settings.Journal.SystemMaxUse = "256M";
      };
  };

  systemd.services."container@codex".serviceConfig = {
    CPUQuota = "600%";
    MemoryHigh = "6G";
    MemoryMax = "8G";
    MemorySwapMax = 0;
    TasksMax = 4096;
  };

  networking.nat = {
    enable = true;
    externalInterface = oggy.externalInterface;
    internalInterfaces = [ "ve-codex" ];
  };
  # Run before the NixOS and Docker filter chains, after conntrack and DNAT.
  networking.nftables.tables.codex-guard = {
    family = "inet";
    content = ''
      set private4 {
        type ipv4_addr
        flags interval
        elements = { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16 }
      }
      chain input {
        type filter hook input priority filter - 10; policy accept;
        iifname "ve-codex" ct state { established, related } accept
        iifname "ve-codex" reject with icmpx type admin-prohibited
      }
      chain forward {
        type filter hook forward priority filter - 10; policy accept;
        iifname "ve-codex" jump egress
      }
      chain egress {
        ct state invalid drop
        meta nfproto ipv6 reject with icmpx type admin-prohibited
        ip saddr != ${config.containers.codex.localAddress} reject
        ct state { established, related } accept
        ip daddr ${oggy.dnsAddress} udp dport 53 accept
        ip daddr ${oggy.dnsAddress} tcp dport 53 accept
        ip daddr @private4 reject with icmpx type admin-prohibited
        accept
      }
    '';
  };
  systemd.services."container@codex" = {
    after = [ "nftables.service" ];
    requires = [ "nftables.service" ];
  };
}
