{ ... }:

{
  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };

    # macOS-specific CLIs (not in nixpkgs or need macOS integration)
    brews = [
      "mas" # Mac App Store CLI
    ];

    casks = [
      "ghostty"
      "logitech-options"
      "slack"
      "discord"
      "raycast"
      "bitwarden"
      "stats"
      "timing"
      "linear-linear"
      "bruno"
      "orbstack"
      "spotify"
      "google-chrome"
      "font-fira-code-nerd-font"
      "tailscale-app"
    ];

    masApps = {
      "Xcode" = 497799835;
      "WhatsApp" = 310633997;
    };
  };
}
