# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{ config, lib, pkgs, ... }:

{
	imports =
		[ # Include the results of the hardware scan.
		./hardware-configuration.nix
		./selfhost.nix
		];

# Use the systemd-boot EFI boot loader.
	boot.loader.systemd-boot.enable = true;
	boot.loader.efi.canTouchEfiVariables = true;

systemd.services.gitnix = {
    description = "Git nix - does nix via git";
    serviceConfig.Type = "oneshot";
    path = with pkgs; [
    	git
    	nixos-rebuild
    ];
    script = ''
      cd "/home/killeik/nixos"
			git pull
			nixos-rebuild switch --flake .
    '';
  };

  services.logind.settings.Login = {
    HandleLidSwitch = "ignore"; # Disable sleep on lid closed.
  };

  systemd.timers.gitnix = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      Unit = "gitnix.service";
    };
  };

 networking.hostName = "oggy"; # Define your hostname.

# Configure network connections interactively with nmcli or nmtui.
	networking.networkmanager.enable = true;

# Set your time zone.
	time.timeZone = "Europe/Moscow";

# Select internationalisation properties.
# i18n.defaultLocale = "en_US.UTF-8";
# console = {
#   font = "Lat2-Terminus16";
#   keyMap = "us";
#   useXkbConfig = true; # use xkb.options in tty.
# };

	virtualisation.docker.enable = true;

	services.openssh = {
		enable = true;
		settings = {
			PasswordAuthentication = false;
			PermitRootLogin = "no";
		};
	};


# Define a user account. Don't forget to set a password with ‘passwd’.
	users.users.killeik = {
		isNormalUser = true;
		openssh.authorizedKeys.keys = ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBT5yrcVE1NHFJS9qnwx+01s47mEQ+RE3IQ8dlLefkI3 killeik@onibrain-2024-07-01"];
		extraGroups = [ "wheel" "docker" ]; # Enable ‘sudo’ for the user.
	};

# List packages installed in system profile.
# You can use https://search.nixos.org/ to find more packages (and options).
	environment.systemPackages = with pkgs; [
		vim # Do not forget to add an editor to edit configuration.nix! The Nano editor is also installed by default.
		wget
		git
	];

# Some programs need SUID wrappers, can be configured further or are
# started in user sessions.
# programs.mtr.enable = true;
# programs.gnupg.agent = {
#   enable = true;
#   enableSSHSupport = true;
# };

# List services that you want to enable:

# Enable the OpenSSH daemon.
# services.openssh.enable = true;

# Open ports in the firewall.
# networking.firewall.allowedTCPPorts = [ ... ];
# networking.firewall.allowedUDPPorts = [ ... ];
# Or disable the firewall altogether.
# networking.firewall.enable = false;

# Copy the NixOS configuration file and link it from the resulting system
# (/run/current-system/configuration.nix). This is useful in case you
# accidentally delete configuration.nix.
# system.copySystemConfiguration = true;

# This option defines the first version of NixOS you have installed on this particular machine,
# and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
#
# Most users should NEVER change this value after the initial install, for any reason,
# even if you've upgraded your system to a new NixOS release.
#
# This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
# so changing it will NOT upgrade your system - see https://nixos.org/manual/nixos/stable/#sec-upgrading for how
# to actually do that.
#
# This value being lower than the current NixOS release does NOT mean your system is
# out of date, out of support, or vulnerable.
#
# Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
# and migrated your data accordingly.
#
# For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
	system.stateVersion = "25.11"; # Did you read the comment?

	nix.settings= {
		experimental-features = [
			"flakes"
			"nix-command"
			"pipe-operators"
		];
	};
}
