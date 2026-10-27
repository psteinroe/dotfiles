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
}
