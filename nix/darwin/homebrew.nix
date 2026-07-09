{ ... }:

{
  homebrew = {
    enable = true;
    # zsh/path.zsh already puts Homebrew on PATH. Avoid running
    # `brew shellenv` from /etc/zshrc for every new terminal tab.
    enableZshIntegration = false;

    onActivation = {
      cleanup = "zap";
      autoUpdate = false;
      upgrade = false;
    };

    taps = [
      "smudge/smudge"
      "nikitabobko/tap"
    ];

    brews = [
      "mole"
      "smudge/smudge/nightlight"
    ];

    casks = [
      "ausweisapp"
      "nikitabobko/tap/aerospace"
      "ghostty"
      "codex-app"
      "logitech-options"
      "slack"
      "discord"
      "raycast"
      "bitwarden"
      "stats"
      "timing"
      "linear"
      "wispr-flow"
      "notion"
      "orbstack"
      "spotify"
      "steam"
      "google-chrome"
      "font-fira-code-nerd-font"
      {
        name = "tailscale-app";
        greedy = true;
      }
    ];
  };
}
