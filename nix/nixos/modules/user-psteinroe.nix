{ pkgs, ... }:

{
  users.users.psteinroe = {
    isNormalUser = true;
    description = "Philipp Steinrötter";
    home = "/home/psteinroe";
    shell = pkgs.zsh;
    linger = true;
    extraGroups = [
      "wheel"
      "docker"
    ];
    openssh.authorizedKeys.keyFiles = [ ../../keys/psteinroe.pub ];
  };

  users.manageLingering = true;
  security.sudo.wheelNeedsPassword = false;
}
