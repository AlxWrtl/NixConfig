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
        { spacer = { small = true; }; }
        "/Applications/Ghostty.app"
        { spacer = { small = true; }; }
        "/Applications/Cursor.app"
        { spacer = { small = true; }; }
      ];
    };

    # === Finder Configuration (should be safe) ===
    finder = {
      # View options
      FXPreferredViewStyle = "clmv";           # Column view by default
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

      # Dock animation optimizations
      "com.apple.dock" = {
        launchanim = false;              # Disable dock launch animations
        autohide-delay = 0.0;            # No delay for dock autohide
        autohide-time-modifier = 0.3;    # Faster dock autohide animation
      };
    };

    # === Screen Saver (should be safe) ===
    screensaver = {
      askForPassword = true;                  # Require password after screensaver
      askForPasswordDelay = 0;                # Require password immediately
    };
  };

  # === DISABLED: Keyboard configuration for testing ===
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = false;
  };

  # === Power Management ===
  # Configure sleep and display settings to match your preferences
  power.sleep = {
    # Turn display off on battery when inactive - For 5 minutes
    # Turn display off on power adapter when inactive - For 5 minutes
    display = 5;                           # Display sleeps after 5 minutes

    # Start Screen Saver when inactive - For 10 minutes
    computer = 10;                         # Computer sleeps after 10 minutes

    # Hard disk sleep can be left default or configured
    harddisk = 10;                         # Hard disk sleeps after 10 minutes
  };
}