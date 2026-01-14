{ ... }:

{
  # Dock settings
  system.defaults.dock = {
    autohide = false;
    show-recents = false;
    persistent-apps = [
      "/Applications/Safari.app"
      "/System/Applications/Mail.app"
      "/System/Applications/Calendar.app"
      "/Applications/Ghostty.app"
      "/Applications/Slack.app"
      "/Applications/Spotify.app"
      "/Applications/Linear.app"
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
    # Raycast settings
    "com.raycast.macos" = {
      raycastGlobalHotkey = "Command-49";  # Cmd+Space
      raycastShouldFollowSystemAppearance = 1;
      raycastPreferredWindowMode = "default";  # or "compact"
      showGettingStartedLink = 0;
    };
  };

  # Screensaver
  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 0;
  };

  # Set wallpaper and disable Spotlight hotkey for Raycast
  system.activationScripts.postActivation.text = ''
    osascript -e 'tell application "System Events" to tell every desktop to set picture to "/Users/psteinroe/Developer/dotfiles/media/wallpaper.jpg" as POSIX file' 2>/dev/null || true

    # Disable Spotlight Cmd+Space (key 64) so Raycast can use it
    /usr/libexec/PlistBuddy -c "Set :AppleSymbolicHotKeys:64:enabled false" ~/Library/Preferences/com.apple.symbolichotkeys.plist 2>/dev/null || true
  '';
}
