{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/profiles/qemu-guest.nix")
    ../../modules/nixos/base.nix
    ./gateway.nix
    ./secrets.nix
  ];

  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";
    content = {
      type = "gpt";
      partitions = {
        boot = {
          size = "1M";
          type = "EF02";
        };
        swap = {
          size = "1G";
          content.type = "swap";
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
          };
        };
      };
    };
  };
  boot.loader.grub.enable = true;
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200n8"
  ];

  networking.hostName = "morok";
  networking.useDHCP = false;
  networking.interfaces.ens3.useDHCP = true;
  services.openssh.settings.PermitRootLogin = "prohibit-password";
  services.openssh.settings.KbdInteractiveAuthentication = false;
  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBT5yrcVE1NHFJS9qnwx+01s47mEQ+RE3IQ8dlLefkI3"
  ];

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };
  system.stateVersion = "26.05";
}
