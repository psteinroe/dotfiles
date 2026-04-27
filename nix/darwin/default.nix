{ pkgs, inputs, username, ... }:

{
  imports = [
    ./homebrew.nix
    ./system.nix
  ];

  # Disable nix-darwin's Nix management (Determinate handles it)
  nix.enable = false;

  # Create /etc/zshrc that loads the nix-darwin environment.
  # Disable nix-darwin's built-in completion init so we don't run `compinit`
  # twice; Home Manager handles completions in ~/.zshrc.
  programs.zsh = {
    enable = true;
    enableCompletion = false;
  };

  # Set primary user for user-specific options
  system.primaryUser = username;

  # Set system state version
  system.stateVersion = 5;

  # Apply overlays
  nixpkgs.overlays = [ inputs.rust-overlay.overlays.default ];

  # Used for backwards compatibility
  nixpkgs.hostPlatform = "aarch64-darwin";
}
