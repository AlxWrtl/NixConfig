{ config, pkgs, lib, inputs, ... }:

{
  # ============================================================================
  # macOS UI/UX AND SECURITY CONFIGURATION
  # ============================================================================

  # ============================================================================
  # NETWORK SECURITY CONFIGURATION
  # ============================================================================

  # === Application Layer Firewall ===
  networking.applicationFirewall = {
    enable = true;                                    # Enable firewall protection
    blockAllIncoming = false;                         # Allow essential incoming connections
    allowSigned = true;                               # Allow signed applications to receive connections
    allowSignedApp = true;                            # Allow downloaded signed applications
    enableStealthMode = true;                         # Enable stealth mode (invisible to port scans)
  };

  system.defaults = {

    # ============================================================================
    # INTERFACE & APPEARANCE
    # ============================================================================

    NSGlobalDomain = {
      # === Visual Appearance ===
      AppleInterfaceStyle = "Dark";                    # Dark mode interface
      AppleFontSmoothing = 1;                          # Better font rendering on external monitors
      AppleShowScrollBars = "WhenScrolling";           # Auto-hide scroll bars

      # === Performance & Animations ===
      NSAutomaticWindowAnimationsEnabled = false;     # Disable window animations for speed
      NSWindowResizeTime = 0.001;                     # Instant window resize

      # === Input & Text Editing ===
      NSAutomaticCapitalizationEnabled = false;       # Disable automatic capitalization
      NSAutomaticDashSubstitutionEnabled = false;     # Disable smart dashes
      NSAutomaticPeriodSubstitutionEnabled = false;   # Disable automatic period substitution
      NSAutomaticQuoteSubstitutionEnabled = false;    # Disable smart quotes
      NSAutomaticSpellingCorrectionEnabled = false;   # Disable automatic spelling correction
      ApplePressAndHoldEnabled = true;                # Enable press-and-hold for accent characters

      # === Keyboard Settings ===
      "com.apple.keyboard.fnState" = true;            # Use F1, F2, etc. as standard function keys
      KeyRepeat = 8;                                  # Fastest possible key repeat
      InitialKeyRepeat = 10;                          # Minimal delay before repeat starts

      # === Mouse & Trackpad Navigation ===
      AppleEnableMouseSwipeNavigateWithScrolls = true; # Two-finger swipe navigation

      # === Regional Settings ===
      AppleICUForce24HourTime = true;                 # 24-hour time format
      AppleMeasurementUnits = "Centimeters";          # Metric measurements
    };

    # ============================================================================
    # DOCK & DESKTOP MANAGEMENT
    # ============================================================================

    dock = {
      # === Layout & Position ===
      orientation = "left";                           # Dock on the left side
      autohide = true;                               # Auto-hide the dock

      # === Icon Appearance ===
      tilesize = 25;                                 # Standard icon size
      largesize = 48;                                # Magnified icon size
      magnification = true;                          # Enable magnification on hover

      # === Behavior ===
      show-recents = false;                          # Don't show recent applications
      minimize-to-application = true;                # Minimize windows into app icon
      mru-spaces = false;                            # Don't auto-rearrange Spaces by usage

      # === Hot Corners (all disabled) ===
      wvous-tl-corner = 1;                          # Top-left: disabled
      wvous-tr-corner = 1;                          # Top-right: disabled
      wvous-bl-corner = 1;                          # Bottom-left: disabled
      wvous-br-corner = 1;                          # Bottom-right: disabled

      # === Mission Control ===
      expose-animation-duration = 0.1;               # Faster Mission Control animations
      expose-group-apps = false;                     # Don't group windows by application

      # === Persistent Applications ===
      persistent-apps = [
        { spacer = { small = true; }; }
        "/Applications/Arc.app"
        "/Applications/Ghostty.app"
        "/Applications/Cursor.app"
        { spacer = { small = true; }; }
      ];
    };

    # ============================================================================
    # FILE MANAGEMENT & FINDER
    # ============================================================================

    finder = {
      # === Default View & Search ===
      FXPreferredViewStyle = "clmv";                 # Column view by default
      FXDefaultSearchScope = "SCcf";                 # Search current folder by default

      # === New Window Behavior ===
      NewWindowTarget = "Other";                     # Open new windows to custom location
      NewWindowTargetPath = "file:///Users/alx/Downloads/"; # Default to Downloads folder

      # === Desktop Items Display ===
      ShowExternalHardDrivesOnDesktop = true;        # Show external drives
      ShowHardDrivesOnDesktop = false;               # Hide internal drives
      ShowMountedServersOnDesktop = true;            # Show network drives
      ShowRemovableMediaOnDesktop = true;            # Show USB drives, etc.
      CreateDesktop = true;                          # Show Desktop folder

      # === File Visibility & Extensions ===
      AppleShowAllExtensions = true;                 # Always show file extensions
      AppleShowAllFiles = false;                     # Hide hidden files by default
      FXEnableExtensionChangeWarning = false;        # Don't warn when changing extensions

      # === Interface Elements ===
      ShowPathbar = true;                           # Show path bar at bottom
      ShowStatusBar = true;                         # Show status bar at bottom
      QuitMenuItem = true;                          # Allow quitting Finder with Cmd+Q

      # === Advanced Sorting ===
      _FXShowPosixPathInTitle = false;              # Don't show full POSIX path in title
      _FXSortFoldersFirst = true;                   # Sort folders before files
      _FXSortFoldersFirstOnDesktop = true;          # Apply folder-first sorting to desktop
    };

    # ============================================================================
    # WORKSPACE & WINDOW MANAGEMENT
    # ============================================================================

    # === Multi-Display Configuration ===
    spaces.spans-displays = false;                   # Each display has separate spaces

    # === Stage Manager ===
    WindowManager = {
      GloballyEnabled = false;                      # Disable Stage Manager globally
      EnableStandardClickToShowDesktop = false;    # Disable Stage Manager click-to-desktop
      StandardHideDesktopIcons = false;            # Keep desktop icons visible
      StandardHideWidgets = true;                   # Hide widgets in normal mode
      StageManagerHideWidgets = true;               # Hide widgets in Stage Manager
    };

    # ============================================================================
    # SECURITY & SYSTEM BEHAVIOR
    # ============================================================================

    # === Screen Security ===
    screensaver = {
      askForPassword = true;                        # Require password after screensaver
      askForPasswordDelay = 0;                      # Require password immediately
    };

    # === Login Window ===
    loginwindow = {
      SHOWFULLNAME = false;                         # Show user avatars instead of username field
    };

    # === Application Security ===
    LaunchServices.LSQuarantine = false;             # Disable quarantine for downloaded apps
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false; # Manual macOS updates only

    # === Input Device Configuration ===
    trackpad = {
      TrackpadRightClick = true;                    # Enable two-finger right-click
      Clicking = true;                              # Enable tap-to-click
      TrackpadThreeFingerDrag = true;               # Enable three-finger drag for window management
    };

    # === Mouse Configuration ===
    ".GlobalPreferences"."com.apple.mouse.scaling" = 3.0; # Mouse sensitivity adjustment

    # ============================================================================
    # ADVANCED SYSTEM PREFERENCES
    # ============================================================================

    CustomUserPreferences = {
      # === Security & Privacy Hardening ===
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false; # Disable personalized advertising

      "com.apple.appstore" = {
        ShowDebugMenu = false;                       # Hide debug options
        AutoUpdateApps = true;                       # Enable automatic security updates
      };

      "com.apple.commerce".AutoUpdate = true;         # Auto-update system and security patches

      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;                # Check for updates automatically
        AutomaticDownload = true;                    # Download updates automatically
        CriticalUpdateInstall = true;                # Install critical security updates
        ConfigDataInstall = true;                    # Install system data files and security updates
      };

      # === Keyboard Shortcuts & Hotkeys ===
      "com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
        # Disable Spotlight search (⌘Space) - using Raycast instead
        "64".enabled = false;
        # Disable Spotlight window (⌘Option+Space)
        "65".enabled = false;
      };

      # === Finder Advanced Settings ===
      "com.apple.finder" = {
        _FXSortFoldersFirst = true;                 # Ensure folders sort first
        FXEnableExtensionChangeWarning = false;    # No warning for extension changes
        NSWindowTabbingEnabled = true;              # Enable Finder window tabs
      };

      # === Spotlight Search Categories ===
      "com.apple.Spotlight".orderedItems = [
        # Enabled categories
        { enabled = 1; name = "APPLICATIONS"; }
        { enabled = 1; name = "DOCUMENTS"; }
        { enabled = 1; name = "DIRECTORIES"; }
        { enabled = 1; name = "IMAGES"; }
        { enabled = 1; name = "MOVIES"; }
        { enabled = 1; name = "MUSIC"; }
        { enabled = 1; name = "PDF"; }
        { enabled = 1; name = "PRESENTATIONS"; }
        { enabled = 1; name = "SPREADSHEETS"; }

        # Disabled categories (reduce noise)
        { enabled = 0; name = "MENU_EXPRESSION"; }
        { enabled = 0; name = "CONTACT"; }
        { enabled = 0; name = "MENU_CONVERSION"; }
        { enabled = 0; name = "MENU_DEFINITION"; }
        { enabled = 0; name = "EVENT_TODO"; }
        { enabled = 0; name = "FONTS"; }
        { enabled = 0; name = "MESSAGES"; }
        { enabled = 0; name = "MENU_OTHER"; }
        { enabled = 0; name = "SYSTEM_PREFS"; }
      ];

      # === Dock Performance Optimizations ===
      "com.apple.dock" = {
        launchanim = false;                         # Disable dock launch animations
        autohide-delay = 0.0;                       # No delay for dock autohide
        autohide-time-modifier = 0.3;               # Faster dock autohide animation
      };

      # === Trackpad Configuration ===
      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        Clicking = true;                            # Enable tap to click
        DragLock = false;                           # Disable drag lock
        TrackpadThreeFingerDrag = true;             # Enable three-finger drag
      };

      # === Universal Clipboard & Handoff ===
      "com.apple.coreservices.useractivityd" = {
        ActivityAdvertisingAllowed = true;          # Allow this Mac to advertise activities
        ActivityReceivingAllowed = true;            # Allow this Mac to receive activities
      };
    };
  };

  # ============================================================================
  # POWER MANAGEMENT
  # ============================================================================

  power.sleep = {
    display = 15;                                   # Display sleeps after 15 minutes
    computer = 30;                                  # Computer sleeps after 30 minutes
    harddisk = 10;                                  # Hard disk sleeps after 10 minutes
  };
}