{ config, pkgs, lib, inputs, ... }:

{
  # macOS UI/UX system defaults configuration

  system.defaults = {

    # === Dock Configuration ===
    dock = {
      autohide = true;                    # Auto-hide the dock
      orientation = "left";               # Dock on the left side
      tilesize = 25;                      # Icon size
      largesize = 48;                     # Magnified icon size
      magnification = true;               # Enable magnification
      show-recents = false;               # Don't show recent applications
      minimize-to-application = true;     # Minimize windows into the application icon
      wvous-br-corner = 1;               # Bottom-right hot corner: disabled
      wvous-bl-corner = 1;               # Bottom-left hot corner: disabled
      wvous-tr-corner = 1;               # Top-right hot corner: disabled
      wvous-tl-corner = 1;               # Top-left hot corner: disabled
      expose-animation-duration = 0.1;    # Faster Mission Control animations
      expose-group-by-app = false;       # Don't group windows by application in Mission Control
      mru-spaces = false;                # Don't automatically rearrange Spaces
      persistent-apps = [                # Pinned applications
        "/Applications/Arc.app"
        "/Applications/Ghostty.app"
        "/Applications/Cursor.app"
      ];
    };

    # === Finder Configuration ===
    finder = {
      # View options
      FXPreferredViewStyle = "Nlsv";           # List view by default
      FXDefaultSearchScope = "SCcf";           # Search current folder by default

      # Desktop options
      ShowExternalHardDrivesOnDesktop = true;  # Show external drives on desktop
      ShowHardDrivesOnDesktop = false;         # Hide internal drives on desktop
      ShowMountedServersOnDesktop = true;      # Show mounted servers on desktop
      ShowRemovableMediaOnDesktop = true;      # Show removable media on desktop

      # File handling
      AppleShowAllExtensions = true;           # Show all file extensions
      AppleShowAllFiles = false;               # Don't show hidden files by default
      FXEnableExtensionChangeWarning = false;  # Don't warn when changing file extensions
      CreateDesktop = true;                    # Show Desktop folder

      # Path and status bar
      ShowPathbar = true;                      # Show path bar
      ShowStatusBar = true;                    # Show status bar

      # Window behavior
      QuitMenuItem = true;                     # Allow quitting Finder with Cmd+Q

      # Advanced options
      _FXShowPosixPathInTitle = false;         # Don't show full POSIX path in title
      _FXSortFoldersFirst = true;              # Sort folders first
    };

    # === Global Preferences ===
    NSGlobalDomain = {
      # Appearance
      AppleInterfaceStyle = "Dark";            # Dark mode
      AppleAccentColor = 1;                    # Blue accent color
      AppleHighlightColor = "0.65 0.85 1.0";  # Blue highlight color

      # Keyboard behavior
      InitialKeyRepeat = 6;                    # Fast initial key repeat (lower = faster)
      KeyRepeat = 6;                           # Fast key repeat (lower = faster)
      ApplePressAndHoldEnabled = false;        # Disable press-and-hold for accented characters

      # Mouse and trackpad
      AppleEnableMouseSwipeNavigateWithScrolls = true;  # Enable swipe navigation
      AppleEnableSwipeNavigateWithScrolls = true;       # Enable swipe navigation

      # Text and input
      NSAutomaticCapitalizationEnabled = false;        # Disable automatic capitalization
      NSAutomaticDashSubstitutionEnabled = false;      # Disable smart dashes
      NSAutomaticPeriodSubstitutionEnabled = false;    # Disable automatic period substitution
      NSAutomaticQuoteSubstitutionEnabled = false;     # Disable smart quotes
      NSAutomaticSpellingCorrectionEnabled = false;    # Disable automatic spelling correction

      # Window behavior
      NSTableViewDefaultSizeMode = 1;                  # Small sidebar icon size
      NSWindowShouldDragOnGesture = true;             # Enable window dragging by clicking anywhere
      NSDocumentSaveNewDocumentsToCloud = false;      # Don't save to iCloud by default

      # Menu behavior
      AppleMenuBarVisibleInFullscreen = true;         # Show menu bar in full screen

      # Function keys
      "com.apple.keyboard.fnState" = true;            # Use F1, F2, etc. as standard function keys

      # Miscellaneous
      AppleShowScrollBars = "Automatic";               # Show scroll bars automatically
      NSNavPanelExpandedStateForSaveMode = true;      # Expand save panels by default
      NSNavPanelExpandedStateForSaveMode2 = true;     # Expand save panels by default
      PMPrintingExpandedStateForPrint = true;         # Expand print panels by default
      PMPrintingExpandedStateForPrint2 = true;        # Expand print panels by default
    };

    # === Trackpad Configuration ===
    trackpad = {
      Clicking = true;                         # Enable tap to click
      Dragging = true;                        # Enable trackpad dragging
      TrackpadRightClick = true;              # Enable right click
      TrackpadThreeFingerDrag = true;         # Enable three finger drag
      TrackpadThreeFingerTapGesture = 2;      # Three finger tap for lookup
      FirstClickThreshold = 1;                # Light click pressure
      SecondClickThreshold = 1;               # Light force click pressure
      TrackpadCornerSecondaryClick = 2;       # Right corner for right click
      TrackpadFiveFingerPinchGesture = 2;     # Five finger pinch for Launchpad
      TrackpadFourFingerVertSwipeGesture = 2; # Four finger swipe up for Mission Control
      TrackpadFourFingerHorizSwipeGesture = 2; # Four finger swipe for app switching
    };

    # === Menu Bar Clock ===
    menuExtraClock = {
      Show24Hour = true;                      # 24-hour time format
      ShowAMPM = false;                       # Don't show AM/PM
      ShowDayOfWeek = true;                   # Show day of week
      ShowDate = 1;                           # Show date (1 = when space allows)
      ShowSeconds = false;                    # Don't show seconds
    };

    # === Security & Privacy ===
    LaunchServices = {
      LSQuarantine = false;                   # Disable quarantine for downloaded applications
    };

    # === Screen Saver ===
    screensaver = {
      askForPassword = true;                  # Require password after screensaver
      askForPasswordDelay = 0;                # Require password immediately
    };

    # === Universal Access ===
    universalaccess = {
      reduceMotion = false;                   # Don't reduce motion (animations)
      reduceTransparency = false;             # Don't reduce transparency
    };

    # === Spaces & Mission Control ===
    spaces = {
      spans-displays = false;                 # Don't span displays with spaces
    };

    # === Control Center (macOS Big Sur+) ===
    controlcenter = {
      BatteryShowPercentage = true;           # Show battery percentage
      Bluetooth = true;                       # Show Bluetooth in Control Center
      Display = true;                         # Show display controls
      Sound = true;                          # Show sound controls
    };
  };

  # Additional UI-related system configuration
  system.keyboard = {
    enableKeyMapping = true;                  # Enable key mapping
    remapCapsLockToEscape = false;           # Don't remap Caps Lock to Escape (optional)
  };
}