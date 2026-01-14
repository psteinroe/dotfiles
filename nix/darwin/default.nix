{ pkgs, username, ... }:

{
  imports = [
    ./homebrew.nix
    ./system.nix
  ];

  # Disable nix-darwin's Nix management (Determinate handles it)
  nix.enable = false;

  # Create /etc/zshrc that loads the nix-darwin environment
  programs.zsh.enable = true;

  # Set primary user for user-specific options
  system.primaryUser = username;

  # Set system state version
  system.stateVersion = 5;

  # Used for backwards compatibility
  nixpkgs.hostPlatform = "aarch64-darwin";
}
