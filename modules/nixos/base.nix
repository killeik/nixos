{ ... }:

{
  time.timeZone = "Europe/Moscow";

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
}
