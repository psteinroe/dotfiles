{ ... }:

{
  # Work around Homebrew API cask loader crashes on casks whose
  # API JSON has an empty `depends_on.macos` object.
  environment.variables.HOMEBREW_NO_INSTALL_FROM_API = "1";

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
        name = "tailscale-app";
        greedy = true;
      }
    ];
  };
}
