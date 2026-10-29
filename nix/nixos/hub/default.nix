# Raspberry Pi 3 (1 GB) home hub: an always-on box at home that runs CLIProxyAPI
# behind Tailscale. Imported together with nixpkgs' sd-image-aarch64 module.
#
# No automated updates: no CI deploys, no nightly updater, no reboots by itself.
# Software and OS updates are occasional and manual (README, Home hub).
let
  hostName = "hub";
in
{
  imports = [
    ../pi-base.nix
    ./cliproxyapi.nix
  ];

  networking.hostName = hostName;

  # Don't compile locally on 1 GB of RAM; anything not substituted or copied in
  # fails instead of building here.
  nix.settings.max-jobs = 0;

  # Tailscale SSH is how hub-login reaches the hub (work tailnet policy in
  # getmateo/devboxes). OpenSSH stays for the LAN.
  services.tailscale.extraSetFlags = [ "--ssh" ];
  # The boot auth key must carry tag:hub
  my.pi.tailscaleUpFlags = [
    "--ssh"
    "--advertise-tags=tag:hub"
  ];
}
