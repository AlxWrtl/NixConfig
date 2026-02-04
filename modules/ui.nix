{
  config,
  pkgs,
  lib,
  ...
}:

let
  # Constants inlined (from constants.nix)
  keyRepeat = 8;
  initialKeyRepeat = 10;
  dockTileSize = 25;
  dockLargeSize = 48;
  windowResizeTime = 0.001;
  exposeAnimationDuration = 0.1;
in

{
  # macOS UI/UX, fonts, and system appearance
  # Consolidated from: ui.nix, fonts.nix, constants.nix

  # ============================================================================
  # FONTS
  # ============================================================================

  fonts.packages = with pkgs; [
    # Programming fonts with Nerd Font icons
    nerd-fonts.meslo-lg
    nerd-fonts.hack
    nerd-fonts.fira-code
    nerd-fonts.jetbrains-mono
    nerd-fonts.sauce-code-pro

    # Additional programming fonts
    cascadia-code
    inconsolata

    # System & international typography
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
  ];

  # ============================================================================
  # NETWORK SECURITY
  # ============================================================================

  networking.applicationFirewall = {
    enable = true;
    blockAllIncoming = false;
    allowSigned = true;
    allowSignedApp = true;
    enableStealthMode = true;
  };

  # ============================================================================
  # SYSTEM DEFAULTS
  # ============================================================================

  system.defaults = {
    NSGlobalDomain = {
      # Visual appearance
      AppleInterfaceStyle = "Dark";
      AppleFontSmoothing = 1;
      AppleShowScrollBars = "WhenScrolling";

      # Performance
      NSAutomaticWindowAnimationsEnabled = false;
      NSWindowResizeTime = windowResizeTime;

      # Input & text
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
      ApplePressAndHoldEnabled = true;

      # Keyboard
      "com.apple.keyboard.fnState" = true;
      KeyRepeat = keyRepeat;
      InitialKeyRepeat = initialKeyRepeat;

      # Mouse & trackpad
      AppleEnableMouseSwipeNavigateWithScrolls = true;

      # Regional
      AppleICUForce24HourTime = true;
      AppleMeasurementUnits = "Centimeters";
    };

    # Dock
    dock = {
      orientation = "left";
      autohide = true;
      tilesize = dockTileSize;
      largesize = dockLargeSize;
      magnification = true;
      show-recents = false;
      minimize-to-application = true;
      mru-spaces = false;

      # Hot corners (all disabled)
      wvous-tl-corner = 1;
      wvous-tr-corner = 1;
      wvous-bl-corner = 1;
      wvous-br-corner = 1;

      # Mission Control
      expose-animation-duration = exposeAnimationDuration;
      expose-group-apps = false;

      # Persistent apps
      persistent-apps = [
        {
          spacer.small = true;
        }
        "/Applications/Arc.app"
        "/Applications/Ghostty.app"
        "/Applications/Visual Studio Code.app"
        {
          spacer.small = true;
        }
      ];
    };

    # Finder
    finder = {
      FXPreferredViewStyle = "clmv";
      FXDefaultSearchScope = "SCcf";
      NewWindowTarget = "Other";
      NewWindowTargetPath = "file://${config.users.users.${config.system.primaryUser}.home}/Downloads/";

      # Desktop items
      ShowExternalHardDrivesOnDesktop = true;
      ShowHardDrivesOnDesktop = false;
      ShowMountedServersOnDesktop = true;
      ShowRemovableMediaOnDesktop = true;
      CreateDesktop = true;

      # File visibility
      AppleShowAllExtensions = true;
      AppleShowAllFiles = false;
      FXEnableExtensionChangeWarning = false;

      # Interface
      ShowPathbar = true;
      ShowStatusBar = true;
      QuitMenuItem = true;

      # Sorting
      _FXShowPosixPathInTitle = false;
      _FXSortFoldersFirst = true;
      _FXSortFoldersFirstOnDesktop = true;
    };

    # Workspace
    spaces.spans-displays = false;

    WindowManager = {
      GloballyEnabled = false;
      EnableStandardClickToShowDesktop = false;
      StandardHideDesktopIcons = false;
      StandardHideWidgets = false;
      StageManagerHideWidgets = true;
    };

    # Security
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };

    loginwindow.SHOWFULLNAME = false;
    LaunchServices.LSQuarantine = true;
    SoftwareUpdate.AutomaticallyInstallMacOSUpdates = false;

    # Input devices
    trackpad = {
      TrackpadRightClick = true;
      Clicking = true;
      TrackpadThreeFingerDrag = true;
    };

    ".GlobalPreferences"."com.apple.mouse.scaling" = 3.0;

    # Advanced preferences
    CustomUserPreferences = {
      "com.apple.AdLib".allowApplePersonalizedAdvertising = false;

      "com.apple.security".GKAutoRearm = true;

      "com.apple.appstore" = {
        ShowDebugMenu = false;
        AutoUpdateApps = true;
      };

      "com.apple.commerce".AutoUpdate = true;

      "com.apple.SoftwareUpdate" = {
        AutomaticCheckEnabled = true;
        AutomaticDownload = true;
        CriticalUpdateInstall = true;
        ConfigDataInstall = true;
      };

      # Disable Spotlight shortcuts (using Raycast)
      "com.apple.symbolichotkeys".AppleSymbolicHotKeys = {
        "64".enabled = false;
        "65".enabled = false;
      };

      "com.apple.finder" = {
        _FXSortFoldersFirst = true;
        FXEnableExtensionChangeWarning = false;
        NSWindowTabbingEnabled = true;
        FinderSpawnTab = false;
      };

      "com.apple.Spotlight".orderedItems = [
        {
          enabled = 1;
          name = "APPLICATIONS";
        }
        {
          enabled = 1;
          name = "DOCUMENTS";
        }
        {
          enabled = 1;
          name = "DIRECTORIES";
        }
        {
          enabled = 1;
          name = "IMAGES";
        }
        {
          enabled = 1;
          name = "MOVIES";
        }
        {
          enabled = 1;
          name = "MUSIC";
        }
        {
          enabled = 1;
          name = "PDF";
        }
        {
          enabled = 1;
          name = "PRESENTATIONS";
        }
        {
          enabled = 1;
          name = "SPREADSHEETS";
        }
        {
          enabled = 0;
          name = "MENU_EXPRESSION";
        }
        {
          enabled = 0;
          name = "CONTACT";
        }
        {
          enabled = 0;
          name = "MENU_CONVERSION";
        }
        {
          enabled = 0;
          name = "MENU_DEFINITION";
        }
        {
          enabled = 0;
          name = "EVENT_TODO";
        }
        {
          enabled = 0;
          name = "FONTS";
        }
        {
          enabled = 0;
          name = "MESSAGES";
        }
        {
          enabled = 0;
          name = "MENU_OTHER";
        }
        {
          enabled = 0;
          name = "SYSTEM_PREFS";
        }
      ];

      "com.apple.dock" = {
        launchanim = false;
        autohide-delay = 0.0;
        autohide-time-modifier = 0.3;
      };

      "com.apple.driver.AppleBluetoothMultitouch.trackpad" = {
        Clicking = true;
        DragLock = false;
        TrackpadThreeFingerDrag = true;
      };

      "com.apple.coreservices.useractivityd" = {
        ActivityAdvertisingAllowed = true;
        ActivityReceivingAllowed = true;
      };
    };
  };

  # ============================================================================
  # POWER MANAGEMENT
  # ============================================================================

  power.sleep = {
    display = 15;
    computer = 30;
    harddisk = 10;
  };

  # ============================================================================
  # FONT ENVIRONMENT
  # ============================================================================

  environment.variables = {
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
    TERMINAL_FONT = "MesloLGS Nerd Font";
    EDITOR_FONT = "JetBrainsMono Nerd Font";
  };
}
