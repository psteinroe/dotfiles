# Shared by the Raspberry Pis (currently only the hub): headless, SSH key-only,
# reachable as <hostName>.local on the LAN until Tailscale is up. Imported together
# with nixpkgs' sd-image-aarch64 module; each host sets networking.hostName.
{
  lib,
  username,
  ...
}:

{
  imports = [ ./pi-tailscale-join.nix ];

  nixpkgs.hostPlatform = "aarch64-linux";

  # The SD image module pulls in profiles/base.nix, which enables ZFS and with it
  # an out-of-tree kernel module build. The Pis only need ext4 and vfat.
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
    # SSH stays reachable on the LAN, the way in if the Pi never joined the tailnet
    allowedTCPPorts = [ 22 ];
    trustedInterfaces = [ "tailscale0" ];
  };

  # Publishes <hostName>.local on the LAN as a fallback to Tailscale
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
    openssh.authorizedKeys.keyFiles = [ ../keys/psteinroe.pub ];
  };
  security.sudo.wheelNeedsPassword = false;

  zramSwap.enable = true;

  # Always-on boxes must never sleep
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
