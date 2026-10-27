# Raspberry Pi 4 (2 GB) in the office: a Tailscale app connector in the hellomateo.de
# tailnet, so only the AI provider domains egress from the office IP. It holds no
# credentials and runs no proxy; the domains, tag:office-connector, and autoApprovers
# live in the tailnet policy (getmateo/devboxes). Imported together with nixpkgs'
# sd-image-aarch64 module, which already ships the Pi 4 firmware and device trees.
let
  hostName = "office-connector";
in
{
  imports = [ ../pi-base.nix ];

  networking.hostName = hostName;

  # Ethernet only. "server" turns on IPv4/IPv6 forwarding, which app connectors
  # need. --snat-subnet-routes stays at its default (on), so egress traffic carries
  # the office IP. Tags can't be set with `tailscale set`; the first login runs
  #   sudo tailscale up --advertise-tags=tag:office-connector --advertise-connector
  services.tailscale = {
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-connector" ];
  };
}
