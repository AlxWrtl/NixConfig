{ config, pkgs, lib, inputs, ... }:

{
  # Restored complete Homebrew configuration with all original apps

  homebrew = {
    enable = true;

      # === Homebrew Global Cask Arguments ===
  # Disable quarantine for all casks to prevent "downloaded from Internet" warnings
  caskArgs = {
    no_quarantine = true;              # Disable quarantine for all casks
  };

  # === Homebrew Casks (GUI Applications) ===
  # All your original macOS-specific and proprietary apps
  casks = [
      # === macOS-Specific System Tools ===
      "1password"                   # Password manager (macOS Keychain integration)
      "onyx"                        # System maintenance (macOS-specific)
      "jordanbaird-ice"             # Menu bar organizer (modern Hidden Bar alternative)
      "logi-options+"               # Logitech Options+ (macOS-specific)
      "lunar"                       # Lunar (macOS-specific)

      # === Development Tools ===
      "docker-desktop"              # Docker Desktop (better macOS integration)
      "visual-studio-code"          # Visual Studio Code (moved from Nix - better macOS integration)

      # === Terminal & Development ===
      "ghostty"                     # GPU-accelerated terminal (native features)
      "cursor"                      # AI-powered code editor (macOS-optimized)

      # === Productivity & Workflow ===
      "raycast"                     # Spotlight replacement (macOS-optimized)
      "notion"                      # All-in-one workspace (native features)

      # === Communication & Social ===
      "discord"                     # Communication (better notifications)
      "spotify"                     # Music streaming (native features)

      # === Media & Entertainment ===
      "vlc"                         # Media player (not available for Apple Silicon via Nix)

      # === Design & Creative Tools ===
      "figma"                       # Design tool (latest features, auto-updates)

      # === Proprietary/Commercial Software ===
      "microsoft-teams"             # Microsoft Teams (corporate features)
      "whatsapp"                    # WhatsApp messaging

      # === Media Servers ===
      "plex-media-server"           # Media server (better integration via Homebrew)

      # === Communication ===
      "readdle-spark"               # Email client (Mac-specific features)

      # === Browsers ===
      "arc"                         # Modern browser
      "google-chrome"               # Chrome browser
    ];

    # === Mac App Store Applications ===
    # Apple ecosystem apps and those requiring App Store licensing
    masApps = {
      # === Apple Productivity Suite ===
      "Pages" = 409201541;           # Apple's word processor
      "Numbers" = 409203825;         # Apple's spreadsheet app
      "Keynote" = 409183694;         # Apple's presentation app

      # === Productivity ===
      "Trello" = 1278508951;         # Project management

      # === System Utilities (App Store exclusive) ===
      "DaisyDisk" = 411643860;       # Disk usage analyzer
    };

    # === Homebrew Taps ===
    # Essential taps for specific tools
    taps = [
      # No additional taps needed - using built-in functionality
    ];

    # === Command Line Tools (Brews) ===
    # macOS-specific or problematic tools in Nix
    brews = [
      # === macOS-Specific CLI Tools ===
      "mas"                          # Mac App Store CLI (macOS-exclusive)
    ];

    # === IMPROVED: Homebrew Management Settings ===
    onActivation = {
      cleanup = "uninstall";          # Remove unlisted packages
      autoUpdate = true;              # Auto-update Homebrew
      upgrade = true;                 # Auto-upgrade packages
    };

    # === Homebrew Global Settings ===
    global = {
      brewfile = true;               # Generate Brewfile
    };
  };

  # === Environment Variables for Homebrew ===
  environment.variables = {
    # Homebrew configuration
    HOMEBREW_NO_ANALYTICS = "1";     # Disable analytics
    HOMEBREW_NO_INSECURE_REDIRECT = "1";  # Disable insecure redirects
    HOMEBREW_CASK_OPTS_NO_BINARIES = "1"; # Don't link binaries for casks

    # Add Homebrew to PATH explicitly
    HOMEBREW_PREFIX = "/opt/homebrew";

    # === ADDED: mas CLI environment improvements ===
    MAS_NO_PROMPT = "1";             # Prevent mas from prompting during automation
  };

  # === Ensure Homebrew is in system PATH ===
  environment.systemPath = [ "/opt/homebrew/bin" "/usr/local/bin" ];
}