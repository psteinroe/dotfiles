{ pkgs, ... }:

let
  tailscaleBootstrap = pkgs.writeShellScript "tailscale-bootstrap" ''
    set -eu

    authkey=/var/lib/tailscale-bootstrap/authkey
    tailscale=${pkgs.tailscale}/bin/tailscale

    # A pre-existing login is authoritative; never replace it with the
    # bootstrap key copied in by nixos-anywhere.
    if "$tailscale" status --json 2>/dev/null \
      | ${pkgs.jq}/bin/jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
      rm -f -- "$authkey"
      echo "Tailscale is already running; removed any stale bootstrap key."
      exit 0
    fi

    if [ ! -r "$authkey" ]; then
      echo "No Tailscale bootstrap key found; skipping enrollment."
      exit 0
    fi

    if "$tailscale" up \
      --auth-key=file:"$authkey" \
      --hostname=psteinroe-dev-hetzner \
      --ssh=false \
      --accept-dns=true \
      --operator=psteinroe; then
      rm -f -- "$authkey"
      echo "Tailscale enrollment succeeded; removed the bootstrap key."
    else
      echo "Tailscale enrollment failed; retaining the bootstrap key for retry." >&2
      exit 1
    fi
  '';
in
{
  services.tailscale = {
    enable = true;
    # Permit direct public WireGuard transport when DERP/direct peer paths are
    # unavailable.  SSH and Mosh remain restricted to tailscale0 above.
    openFirewall = true;
  };

  systemd.services.tailscale-bootstrap = {
    description = "Enroll this host in Tailscale on first boot";
    wantedBy = [ "multi-user.target" ];
    unitConfig = {
      StartLimitIntervalSec = 300;
      StartLimitBurst = 10;
    };
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = tailscaleBootstrap;
      Restart = "on-failure";
      RestartSec = "10s";
    };
  };
}
