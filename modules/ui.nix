{
  config,
  pkgs,
  lib,
  ...
}:

let
  keyRepeat = 8;
  initialKeyRepeat = 10;
  dockTileSize = 25;
  dockLargeSize = 48;
  windowResizeTime = 0.001;
  exposeAnimationDuration = 0.1;
in

{

  fonts.packages = [
    pkgs.nerd-fonts.meslo-lg
    pkgs.nerd-fonts.hack
    pkgs.nerd-fonts.fira-code
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.nerd-fonts.sauce-code-pro
    pkgs.cascadia-code
    pkgs.inconsolata
    pkgs.noto-fonts
    pkgs.noto-fonts-cjk-sans
    pkgs.noto-fonts-color-emoji
  ];

  networking.applicationFirewall = {
    enable = true;
    blockAllIncoming = false;
    allowSigned = true;
    allowSignedApp = true;
    enableStealthMode = true;
  };

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

      # Spotlight: disable only unwanted categories (others enabled by default)
      "com.apple.Spotlight".orderedItems = [
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

  power.sleep = {
    display = 15;
    computer = 30;
    harddisk = 10;
  };

  environment.variables = {
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
    TERMINAL_FONT = "MesloLGS Nerd Font";
    EDITOR_FONT = "JetBrainsMono Nerd Font";
  };
}
