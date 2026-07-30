{
  inputs,
  username,
  system,
  ...
}:

{
  imports = [
    ./homebrew.nix
    ./system.nix
  ];

  # Disable nix-darwin's Nix management (Determinate handles it). Update
  # Determinate's supported custom settings file after activation instead of
  # claiming it through environment.etc, which conflicts with its regular file.
  nix.enable = false;
  system.activationScripts.postActivation.text = ''
    /bin/cat > /etc/nix/nix.custom.conf <<'EOF'
    # Managed by psteinroe/dotfiles.
    extra-substituters = https://cache.numtide.com
    extra-trusted-substituters = https://cache.numtide.com
    extra-trusted-public-keys = niks3.numtide.com-1:DTx8wZduET09hRmMtKdQDxNNthLQETkc/yaX7M4qK0g=
    EOF
    /bin/chmod 0644 /etc/nix/nix.custom.conf
  '';

  # Create /etc/zshrc that loads the nix-darwin environment.
  # Disable nix-darwin's built-in completion init so we don't run `compinit`
  # twice; Home Manager handles completions in ~/.zshrc.
  programs.zsh = {
    enable = true;
    enableCompletion = false;
    enableBashCompletion = false;
    # Home Manager installs starship, so don't spend startup time initialising
    # nix-darwin's default prompt first just to replace it later.
    promptInit = "";
  };

  # Set primary user for user-specific options
  system.primaryUser = username;

  # Set system state version
  system.stateVersion = 5;

  # Apply overlays
  nixpkgs.overlays = [ inputs.rust-overlay.overlays.default ];

  nixpkgs.hostPlatform = system;
}
