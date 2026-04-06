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
      "manaflow-ai/cmux"
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
      "linear-linear"
      "bruno"
      "cmux"
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
