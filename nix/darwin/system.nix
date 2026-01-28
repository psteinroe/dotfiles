{ ... }:

{
  # Menu bar / Control Center
  system.defaults.controlcenter = {
    Bluetooth = true;
    Sound = true;
    BatteryShowPercentage = true;
  };

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
      "/System/Applications/Notes.app"
    ];
  };

  # Finder settings
  system.defaults.finder = {
    AppleShowAllExtensions = true;
    ShowPathbar = true;
    FXPreferredViewStyle = "clmv"; # Column view
    _FXShowPosixPathInTitle = true;
    FXRemoveOldTrashItems = true;
  };

  # Global settings
  system.defaults.NSGlobalDomain = {
    AppleInterfaceStyle = "Dark";
    KeyRepeat = 2;
    InitialKeyRepeat = 15;
    ApplePressAndHoldEnabled = false; # Enable key repeat
    NSAutomaticCapitalizationEnabled = false;
    NSAutomaticSpellingCorrectionEnabled = false;
    # Scroll direction: false = traditional (not natural)
    "com.apple.swipescrolldirection" = false;
    AppleEnableSwipeNavigateWithScrolls = false;
  };

  # Trackpad settings
  system.defaults.trackpad = {
    Clicking = true; # Tap to click
    TrackpadThreeFingerDrag = true;
  };

  # Custom preferences
  system.defaults.CustomUserPreferences = {
    # Mouse speed: range -1 (slowest) to 3 (fastest), default ~0.875
    ".GlobalPreferences"."com.apple.mouse.scaling" = 2.0;
    # Safari: enable dev mode manually (Settings > Advanced > Show features for web developers)
    # Can't be set via nix due to sandboxed preferences
    "com.apple.WindowManager" = {
      StandardHideWidgets = 1;
      StageManagerHideWidgets = 1;
    };
    # Raycast settings
    "com.raycast.macos" = {
      raycastGlobalHotkey = "Command-49"; # Cmd+Space (set manually in System Settings first)
      raycastShouldFollowSystemAppearance = 1;
      raycastPreferredWindowMode = "default";
      showGettingStartedLink = 0;
    };
  };

  # Keyboard
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToControl = true;
  };

  # Screensaver
  system.defaults.screensaver = {
    askForPassword = true;
    askForPasswordDelay = 0;
  };

  # Set wallpaper
  system.activationScripts.postActivation.text = ''
    osascript -e 'tell application "System Events" to tell every desktop to set picture to "/Users/psteinroe/Developer/dotfiles/media/wallpaper.jpg" as POSIX file' 2>/dev/null || true
  '';
}
