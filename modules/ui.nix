{ config, pkgs, lib, inputs, ... }:

{
  # macOS UI/UX system defaults configuration

  system.defaults = {
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
      expose-group-apps = false;         # Don't group windows by application in Mission Control
      mru-spaces = false;                # Don't automatically rearrange Spaces
      persistent-apps = [
        { spacer = { small = true; }; }
        "/Applications/Arc.app"
        "/Applications/Ghostty.app"
        "/Applications/Cursor.app"
        { spacer = { small = true; }; }
      ];
    };

    # === Finder Configuration ===
    finder = {
      # View options
      FXPreferredViewStyle = "clmv";           # List view by default (required for grouping)
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
      _FXSortFoldersFirstOnDesktop = true;     # Sort folders first on desktop
    };

    # === Global Preferences (minimal set) ===
    NSGlobalDomain = {
      # Appearance
      AppleInterfaceStyle = "Dark";            # Dark mode

      # Animation and performance optimizations
      NSAutomaticWindowAnimationsEnabled = false;     # Disable window animations
      NSWindowResizeTime = 0.001;                     # Instant window resize

      # Text and input (should be safe)
      NSAutomaticCapitalizationEnabled = false;        # Disable automatic capitalization
      NSAutomaticDashSubstitutionEnabled = false;      # Disable smart dashes
      NSAutomaticPeriodSubstitutionEnabled = false;    # Disable automatic period substitution
      NSAutomaticQuoteSubstitutionEnabled = false;     # Disable smart quotes
      NSAutomaticSpellingCorrectionEnabled = false;    # Disable automatic spelling correction
      ApplePressAndHoldEnabled = true;                 # Enable press-and-hold for accent characters

      # Function keys
      "com.apple.keyboard.fnState" = true;            # Use F1, F2, etc. as standard function keys

      # Keyboard repeat speed
      KeyRepeat = 8;                                   # Fastest possible key repeat (1 = maximum speed)
      InitialKeyRepeat = 10;                           # Minimal delay before repeat (10 = very fast start)

    };

    # === Security & Privacy (should be safe) ===
    LaunchServices = {
      LSQuarantine = false;                   # Disable quarantine for downloaded applications
    };

    # === Additional Security Preferences ===
    SoftwareUpdate = {
      AutomaticallyInstallMacOSUpdates = false;  # Don't auto-install macOS updates
    };

    # === Spotlight Configuration ===
    spaces = {
      spans-displays = false;                 # Don't span Spaces across displays
    };

    # === Stage Manager Configuration ===
    WindowManager = {
      EnableStandardClickToShowDesktop = false; # Disable Stage Manager
      StandardHideDesktopIcons = false;         # Keep desktop icons visible
      StandardHideWidgets = true;               # Hide widgets
      StageManagerHideWidgets = true;           # Hide widgets in Stage Manager
      GloballyEnabled = false;                  # Disable Stage Manager globally
    };

    # Disable Spotlight search hotkey and hide menubar icon
    CustomUserPreferences = {
      "com.apple.symbolichotkeys" = {
        AppleSymbolicHotKeys = {
          # Disable Spotlight search (⌘Space)
          "64" = {
            enabled = false;
            value = {
              parameters = [ 32 49 1048576 ];
              type = "standard";
            };
          };
          # Disable Spotlight window (⌘Option+Space)
          "65" = {
            enabled = false;
            value = {
              parameters = [ 32 49 1572864 ];
              type = "standard";
            };
          };
        };
      };

      # Finder sorting preferences
      "com.apple.finder" = {
        _FXSortFoldersFirst = true;              # Sort folders first
        FXEnableExtensionChangeWarning = false; # Don't warn when changing extensions
        NSWindowTabbingEnabled = true;           # Enable Finder tabs
      };

      # Spotlight search categories
      "com.apple.Spotlight" = {
        orderedItems = [
          { enabled = 1; name = "APPLICATIONS"; }
          { enabled = 1; name = "DOCUMENTS"; }
          { enabled = 1; name = "DIRECTORIES"; }
          { enabled = 1; name = "IMAGES"; }
          { enabled = 1; name = "MOVIES"; }
          { enabled = 1; name = "MUSIC"; }
          { enabled = 1; name = "PDF"; }
          { enabled = 1; name = "PRESENTATIONS"; }
          { enabled = 1; name = "SPREADSHEETS"; }
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
      };

      # Dock animation optimizations
      "com.apple.dock" = {
        launchanim = false;              # Disable dock launch animations
        autohide-delay = 0.0;            # No delay for dock autohide
        autohide-time-modifier = 0.3;    # Faster dock autohide animation
      };
    };

    # === Screen Saver ===
    screensaver = {
      askForPassword = true;                  # Require password after screensaver
      askForPasswordDelay = 0;                # Require password immediately
    };
  };

  # === Power Management ===
  power.sleep = {
    display = 5;                           # Display sleeps after 5 minutes
    computer = 10;                         # Computer sleeps after 10 minutes

    # Hard disk sleep can be left default or configured
    harddisk = 10;                         # Hard disk sleeps after 10 minutes
  };
}