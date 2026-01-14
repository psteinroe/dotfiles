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
      "withgraphite/tap"
    ];

    # macOS-specific CLIs (not in nixpkgs or need macOS integration)
    brews = [
      "mas"       # Mac App Store CLI
      "graphite"  # Not in nixpkgs

      # iOS development
      "cocoapods"
      "fastlane"
      "watchman"
    ];

    # Only apps that can't be nix-casks
    casks = [
      "ghostty"          # nixpkgs broken on Darwin, needs signed binary
      "logitech-options" # .pkg installer, hardware driver
    ];

    masApps = {
      "Xcode" = 497799835;
      "WhatsApp" = 310633997;
    };
  };
}
