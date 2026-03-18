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

    # Menu bar clock
    menuExtraClock = {
      IsAnalog = false;
      Show24Hour = true;
      ShowDate = 1;
      ShowDayOfWeek = false;
      ShowSeconds = false;
    };

    # Security
    screensaver = {
      askForPassword = true;
      askForPasswordDelay = 0;
    };

    screencapture.type = "png";

    loginwindow.SHOWFULLNAME = false;
    LaunchServices.LSQuarantine = false;
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
        FXEnableExtensionChangeWarning = false;
        NSWindowTabbingEnabled = true;
        FinderSpawnTab = false;
        ShowRecentTags = false;

        # Desktop: Use Stacks grouped by Kind
        FXPreferredGroupBy = "Kind";
        FXArrangeGroupViewBy = "Name";
        DesktopViewSettings = {
          GroupBy = "Kind";
          IconViewSettings = {
            arrangeBy = "dateAdded";
            iconSize = 64;
            textSize = 12;
            gridSpacing = 54;
            showIconPreview = true;
            showItemInfo = false;
            labelOnBottom = true;
          };
        };

        # iCloud Drive sync
        FXICloudDriveEnabled = true;
        FXICloudDriveDesktop = true;
        FXICloudDriveDocuments = true;

        # Column view defaults
        FK_StandardViewOptions2.ColumnViewOptions = {
          ColumnWidth = 245;
          FontSize = 13;
          ShowPreview = true;
          ShowIconThumbnails = true;
          ColumnShowFolderArrow = true;
          ColumnShowIcons = true;
          PreviewDisclosureState = true;
          ArrangeBy = "dnam";
          SharedArrangeBy = "kipl";
        };
      };

      # Spotlight: disable only unwanted categories (others enabled by default)
      "com.apple.Spotlight".orderedItems = [
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

      # Touch Bar: mini control strip (brightness, volume, mute)
      "com.apple.controlstrip".MiniCustomized = [
        "com.apple.system.brightness"
        "com.apple.system.volume"
        "com.apple.system.mute"
      ];

      # Input source indicator visible in menu bar
      "com.apple.TextInputMenu".visible = true;

      # NSGlobalDomain extras (not in typed options)
      NSGlobalDomain = {
        # Text replacements
        NSUserDictionaryReplacementItems = [
          {
            on = 1;
            replace = "jrv";
            "with" = "J'arrive !";
          }
          {
            on = 1;
            replace = "omw";
            "with" = "On my way!";
          }
          {
            on = 1;
            replace = "lol";
            "with" = "lol";
          }
        ];

        AppleEnableSwipeNavigateWithScrolls = true;
        "com.apple.trackpad.forceClick" = true;
        AppleWindowTabbingMode = "always";
        AppleMiniaturizeOnDoubleClick = false;
        NSWindowShouldDragOnGesture = true;
        NSDocumentSaveNewDocumentsToCloud = false;
        NSNavPanelExpandedStateForSaveMode = true;
        NSNavPanelExpandedStateForSaveMode2 = true;
        PMPrintingExpandedStateForPrint = true;
        PMPrintingExpandedStateForPrint2 = true;
        NSTableViewDefaultSizeMode = 1;
      };

      # Window Manager extras
      "com.apple.WindowManager" = {
        EnableTiledWindowMargins = false;
        AppWindowGroupingBehavior = true;
      };

      # Siri disabled (using Raycast)
      "com.apple.assistant.support"."Assistant Enabled" = false;

      # Screensaver: Fliqlo, 2 min idle, no clock overlay
      "com.apple.screensaver" = {
        idleTime = 120;
        showClock = false;
      };

      # Screen capture
      "com.apple.screencapture".style = "display";

      # Trackpad gestures (full declaration)
      "com.apple.AppleMultitouchTrackpad" = {
        Clicking = true;
        TrackpadRightClick = true;
        TrackpadThreeFingerDrag = true;
        TrackpadThreeFingerTapGesture = 0;
        TrackpadFourFingerHorizSwipeGesture = 2;
        TrackpadFourFingerVertSwipeGesture = 2;
        TrackpadFourFingerPinchGesture = 2;
        TrackpadFiveFingerPinchGesture = 2;
        TrackpadTwoFingerDoubleTapGesture = 1;
        TrackpadTwoFingerFromRightEdgeSwipeGesture = 3;
        TrackpadPinch = true;
        TrackpadRotate = true;
        TrackpadMomentumScroll = true;
        USBMouseStopsTrackpad = false;
        DragLock = false;
        FirstClickThreshold = 1;
        SecondClickThreshold = 1;
        ActuateDetents = true;
        ForceSuppressed = false;
      };

    };
  };

  # Power managed by launchd daemon in services.nix (pmset)
  # Do not use power.sleep here — it would be overridden

  # Wallpaper (applied on rebuild)
  system.activationScripts.postActivation.text = lib.mkAfter ''
    wallpaper="${../wallpapers/wallpaper.jpg}"
    if [ -f "$wallpaper" ]; then
      osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$wallpaper\""
      echo "Wallpaper set: $wallpaper"
    fi
  '';

  environment.variables = {
    FONTCONFIG_FILE = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
    TERMINAL_FONT = "MesloLGS Nerd Font";
    EDITOR_FONT = "JetBrainsMono Nerd Font";
  };
}
