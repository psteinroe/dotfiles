{ pkgs, username, ... }:

{
  imports = [
    ./homebrew.nix
    ./system.nix
  ];

  # Nix configuration
  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" username ];
    };
  };

  # Enable nix-daemon
  services.nix-daemon.enable = true;

  # Create /etc/zshrc that loads the nix-darwin environment
  programs.zsh.enable = true;

  # Set system state version
  system.stateVersion = 5;

  # Used for backwards compatibility
  nixpkgs.hostPlatform = "aarch64-darwin";
}
