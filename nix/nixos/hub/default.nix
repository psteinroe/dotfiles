# Raspberry Pi 3 (1 GB) home hub: an always-on box at home that runs CLIProxyAPI
# behind Tailscale. Imported together with nixpkgs' sd-image-aarch64 module.
let
  hostName = "hub";
in
{
  imports = [
    ../pi-base.nix
    ./cliproxyapi.nix
  ];

  networking.hostName = hostName;

  # Pulls main of the public repo every night and switches to it (evaluated and
  # built on the Pi, mostly substituted). No reboots: a new kernel takes effect at
  # the next power cycle. allowReboot = true would reboot only when the kernel,
  # modules or initrd changed. hub-rebuild still deploys right away.
  system.autoUpgrade = {
    enable = true;
    flake = "github:psteinroe/dotfiles#${hostName}";
    # The flake's own lock file pins nixpkgs; --upgrade would only touch channels
    upgrade = false;
    dates = "04:00";
    randomizedDelaySec = "45min";
    allowReboot = false;
  };
}
