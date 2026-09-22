{
  lib,
  t3codeTransport ? "tailscale-serve",
  ...
}:

{
  services.openssh = {
    enable = true;
    openFirewall = false;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
      AllowUsers = [ "psteinroe" ];
      X11Forwarding = false;
      AllowAgentForwarding = false;
      AllowTcpForwarding = "yes";
      GatewayPorts = "no";
      PermitTunnel = false;
      MaxAuthTries = 3;
      LoginGraceTime = 30;
    };
  };

  networking.firewall = {
    enable = true;
    # Do not open SSH or Mosh on the public interfaces.  These rules apply
    # only after Tailscale has created its interface.
    interfaces."tailscale0" = {
      allowedTCPPorts = [ 22 ] ++ lib.optional (t3codeTransport == "tailscale-direct") 3773;
      allowedUDPPortRanges = [
        {
          from = 60000;
          to = 61000;
        }
      ];
    };
  };
}
