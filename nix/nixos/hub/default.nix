# Raspberry Pi 3 (1 GB) home hub: an always-on box at home that runs CLIProxyAPI
# behind Tailscale. Imported together with nixpkgs' sd-image-aarch64 module.
{
  lib,
  username,
  ...
}:

let
  hostName = "hub";
in
{
  imports = [ ./cliproxyapi.nix ];

  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = hostName;

  # The SD image module pulls in profiles/base.nix, which enables ZFS and with it
  # an out-of-tree kernel module build. The hub only needs ext4 and vfat.
  boot.supportedFilesystems.zfs = lib.mkForce false;
  hardware.enableRedistributableFirmware = true;

  # Ethernet with DHCP (the NixOS default). For Wi-Fi instead, keep the PSK out of
  # Git and the store: put `psk_home=...` into /var/lib/wireless.env on the Pi, then
  #   networking.wireless = {
  #     enable = true;
  #     secretsFile = "/var/lib/wireless.env";
  #     networks."<SSID>".pskRaw = "ext:psk_home";
  #   };
  networking.firewall = {
    enable = true;
    # SSH stays reachable on the LAN, which is the only way in before `tailscale up`
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # Publishes hub.local on the LAN for the first login
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };

  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  services.tailscale.enable = true;

  users.mutableUsers = false;
  users.users.${username} = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
    openssh.authorizedKeys.keyFiles = [ ../../keys/psteinroe.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  zramSwap.enable = true;

  # The hub must never sleep
  systemd.targets = lib.genAttrs [ "sleep" "suspend" "hibernate" "hybrid-sleep" ] (_: {
    enable = false;
  });

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      # hub-rebuild copies closures as psteinroe and builds here
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 14d";
    };
  };

  documentation = {
    nixos.enable = false;
    man.enable = false;
    info.enable = false;
    doc.enable = false;
  };

  time.timeZone = "Europe/Berlin";

  system.stateVersion = "26.11";
}
