{ ... }:

{
  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";
      autoUpdate = true;
      upgrade = true;
    };

    taps = [
      "smudge/smudge"
    ];

    # macOS-specific CLIs (not in nixpkgs or need macOS integration)
    brews = [
      "mas" # Mac App Store CLI
      "smudge/smudge/nightlight"
    ];

    casks = [
      "ausweisapp"
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
      {
        name = "tailscale-app"; # GUI app + Network Extension (CLI comes from nixpkgs)
        greedy = true; # keep auto-updating cask on rebuild
      }
    ];

    masApps = {
      "Xcode" = 497799835;
      "WhatsApp" = 310633997;
    };
  };
}
