{ config, pkgs, ... }:
{
  # The persistent root is a Btrfs subvolume, prepared before first activation.
  containers.codex = {
    autoStart = true;
    ephemeral = false;
    privateUsers = "pick";
    privateNetwork = true;
    hostAddress = "10.231.40.1";
    localAddress = "10.231.40.2";
    config = { pkgs, ... }: {
      system.stateVersion = "25.11";
      networking.hostName = "codex";
      networking.useHostResolvConf = false;
      networking.nameservers = [ "192.168.1.1" ];
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
        openssh.authorizedKeys.keys = config.users.users.killeik.openssh.authorizedKeys.keys;
      };
      environment.systemPackages = with pkgs; [
        codex t3code git ripgrep tmux curl jq nodejs python3 uv gcc gnumake pkg-config
      ];
      programs.nix-ld.enable = true;
      environment.localBinInPath = true;
      systemd.services.t3 = {
        description = "T3 Code web interface";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        environment = {
          HOME = "/home/codex";
          PATH = pkgs.lib.mkForce "/home/codex/.local/bin:${pkgs.lib.makeBinPath (with pkgs; [ codex git ripgrep nodejs bash coreutils openssh ])}";
        };
        serviceConfig = {
          User = "codex";
          WorkingDirectory = "/home/codex";
          ExecStart = "${pkgs.t3code}/bin/t3 serve --host 0.0.0.0 --port 3773";
          Restart = "on-failure";
          RestartSec = 10;
          UMask = "0077";
        };
      };
      networking.firewall.allowedTCPPorts = [ 3773 ];
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
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
    externalInterface = "enp0s20f0u3u4";
    internalInterfaces = [ "ve-codex" ];
  };
  # Host access is blocked by the host firewall. Restrict forwarded traffic too.
  networking.firewall.extraCommands = ''
    iptables -N CODEX-EGRESS 2>/dev/null || true
    iptables -F CODEX-EGRESS
    iptables -A CODEX-EGRESS -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A CODEX-EGRESS -d 192.168.1.1 -p udp --dport 53 -j ACCEPT
    iptables -A CODEX-EGRESS -d 192.168.1.1 -p tcp --dport 53 -j ACCEPT
    for subnet in 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 169.254.0.0/16; do
      iptables -A CODEX-EGRESS -d "$subnet" -j REJECT
    done
    iptables -A CODEX-EGRESS -j ACCEPT
    iptables -C FORWARD -i ve-codex -j CODEX-EGRESS 2>/dev/null || iptables -I FORWARD 1 -i ve-codex -j CODEX-EGRESS
    iptables -C INPUT -i ve-codex -m conntrack --ctstate NEW -j REJECT 2>/dev/null || iptables -I INPUT 1 -i ve-codex -m conntrack --ctstate NEW -j REJECT
  '';
  networking.firewall.extraStopCommands = ''
    iptables -D FORWARD -i ve-codex -j CODEX-EGRESS 2>/dev/null || true
    iptables -D INPUT -i ve-codex -m conntrack --ctstate NEW -j REJECT 2>/dev/null || true
    iptables -F CODEX-EGRESS 2>/dev/null || true
    iptables -X CODEX-EGRESS 2>/dev/null || true
  '';
}
