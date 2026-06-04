{ ... }:

{
  # Work around Homebrew 5.1.7 API cask loader crashes on casks whose
  # API JSON has an empty `depends_on.macos` object.
  environment.etc."homebrew/brew.env".text = ''
    HOMEBREW_NO_INSTALL_FROM_API=1
  '';

  homebrew = {
    enable = true;
    onActivation = {
      cleanup = "zap";
      autoUpdate = false;
      upgrade = false;
    };

    taps = [
      "smudge/smudge"
      "nikitabobko/tap"
    ];

    # macOS-specific CLIs (not in nixpkgs or need macOS integration)
    brews = [
      "mole" # macOS cleanup & optimization
      "smudge/smudge/nightlight"
    ];

    casks = [
      "ausweisapp"
      "nikitabobko/tap/aerospace"
      "ghostty"
      "logitech-options"
      "slack"
      "discord"
      "raycast"
      "bitwarden"
      "stats"
      "timing"
      "linear"
      "notion"
      "orbstack"
      "spotify"
      "steam"
      "codex-app"
      "google-chrome"
      "font-fira-code-nerd-font"
      {
        name = "tailscale-app"; # GUI app + Network Extension (CLI comes from nixpkgs)
        greedy = true; # keep auto-updating cask on rebuild
      }
    ];
  };
}
