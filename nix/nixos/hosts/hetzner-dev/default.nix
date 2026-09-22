{ modulesPath, ... }:

{
  imports = [
    # Hetzner Cloud's x86_64 instances run as QEMU/KVM guests.  Keep the
    # installer scan profile as well so hardware not recognized at install
    # time still gets the conservative firmware defaults.
    "${modulesPath}/profiles/qemu-guest.nix"
    "${modulesPath}/installer/scan/not-detected.nix"
    ./disko.nix
    ../../modules/base.nix
    ../../modules/user-psteinroe.nix
    ../../modules/openssh-tailnet.nix
    ../../modules/tailscale.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking = {
    hostName = "psteinroe-dev-hetzner";
    # First boot must acquire public egress before the private tailnet exists.
    # Hetzner Cloud supplies addressing and routes through DHCP.
    useDHCP = true;
  };

  system.stateVersion = "24.11";
}
