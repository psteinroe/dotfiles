{ pkgs, ... }:

{
  boot.loader.grub = {
    enable = true;
    devices = [ "/dev/sda" ];
    efiSupport = true;
    efiInstallAsRemovable = true;
  };
  boot.loader.efi.canTouchEfiVariables = false;

  nix = {
    settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      auto-optimise-store = true;
      substituters = [
        "https://cache.nixos.org/"
        "https://cache.numtide.com"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g="
      ];
      trusted-users = [
        "root"
        "@wheel"
      ];
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 30d";
    };
  };

  programs.nix-ld.enable = true;
  programs.zsh.enable = true;

  virtualisation.docker = {
    enable = true;
    daemon.settings = {
      # Published container ports must not be exposed on the public interface
      # by default.  Services can still opt into a different bind address.
      ip = "127.0.0.1";
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    git
    mosh
    tmux
  ];
}
