{ username, ... }:

{
  # Dock settings
  system.defaults.dock = {
    autohide = false;
    show-recents = false;
    persistent-apps = [
      "/Applications/Safari.app"
      "/System/Applications/Mail.app"
      "/System/Applications/Calendar.app"
      "/Applications/Slack.app"
      "/Applications/Ghostty.app"
      "/Applications/Linear.app"
      "/Applications/Spotify.app"
      "/System/Applications/System Settings.app"
    ];
  };

  # Finder settings
  system.defaults.finder = {
    AppleShowAllExtensions = true;
    ShowPathbar = true;
    FXPreferredViewStyle = "clmv"; # Column view
    _FXShowPosixPathInTitle = true;
  };

  # Global settings
  system.defaults.NSGlobalDomain = {
    AppleInterfaceStyle = "Dark";
    KeyRepeat = 2;
    InitialKeyRepeat = 15;
    ApplePressAndHoldEnabled = false; # Enable key repeat
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
  };

  # Trackpad settings
  system.defaults.trackpad = {
    Clicking = true; # Tap to click
    TrackpadThreeFingerDrag = true;
  };

  # Disable desktop widgets
  system.defaults.CustomUserPreferences = {
    "com.apple.WindowManager" = {
      StandardHideWidgets = 1;
      StageManagerHideWidgets = 1;
    };
  };

  # Screensaver
  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 0;
  };

  # Set wallpaper
  system.activationScripts.postActivation.text = ''
    osascript -e 'tell application "System Events" to tell every desktop to set picture to "/Users/${username}/.dotfiles/media/wallpaper.jpg" as POSIX file' 2>/dev/null || true
  '';
}
