# Raspberry Pi 3 (1 GB) home hub: an always-on box at home that runs CLIProxyAPI
# behind Tailscale. Imported together with nixpkgs' sd-image-aarch64 module.
#
# Deployed by .github/workflows/hub-deploy.yml: a GitHub aarch64-linux runner
# evaluates and builds every merge to main, then copies the finished closure here
# over Tailscale SSH and activates it with sudo. The Pi never evaluates or builds,
# has no nightly updater and never reboots by itself; a new kernel takes effect at
# the next manual reboot.
let
  hostName = "hub";
in
{
  imports = [
    ../pi-base.nix
    ./cliproxyapi.nix
  ];

  networking.hostName = hostName;

  # No local builds: anything not copied in or substituted fails instead of
  # compiling on 1 GB of RAM, so `nixos-rebuild` on the Pi itself doesn't work.
  nix.settings.max-jobs = 0;

  # Tailscale SSH is how CI reaches the hub (tag:hub-deploy → tag:hub in the tailnet
  # policy). OpenSSH stays for the LAN.
  services.tailscale.extraSetFlags = [ "--ssh" ];
  # The boot auth key must carry tag:hub
  my.pi.tailscaleUpFlags = [
    "--ssh"
    "--advertise-tags=tag:hub"
  ];
}
