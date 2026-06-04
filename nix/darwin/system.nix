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
    autohide = true;
    show-recents = false;
    # Reduce Dock, Mission Control, and Spaces-related animations
    expose-animation-duration = 0.0;
    launchanim = false;
    autohide-delay = 0.0;
    autohide-time-modifier = 0.0;
    mru-spaces = false;
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
    NSAutomaticWindowAnimationsEnabled = false;
    NSUseAnimatedFocusRing = false;
    NSWindowResizeTime = 0.001;
    # Scroll direction: false = traditional (not natural)
    "com.apple.swipescrolldirection" = false;
    AppleEnableSwipeNavigateWithScrolls = false;
  };

  # Accessibility
  # `com.apple.universalaccess` is TCC-protected on recent macOS releases and
  # can make `darwin-rebuild` fail with "Could not write domain" when the
  # launching terminal is not allowed to modify it. Keep this best-effort in
  # postActivation below instead of nix-darwin's fatal defaults writer.

  # Trackpad settings
  system.defaults.trackpad = {
    Clicking = false; # Require physical click (no tap)
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
    # Disable animation when switching screens/spaces or opening apps. This can
    # fail without Full Disk Access for the terminal app, so don't fail rebuilds.
    /usr/bin/defaults write com.apple.universalaccess reduceMotion -bool true 2>/dev/null || true

    osascript -e 'tell application "System Events" to tell every desktop to set picture to "/Users/psteinroe/Developer/dotfiles/media/wallpaper.jpg" as POSIX file' 2>/dev/null || true
  '';
}
