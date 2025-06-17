{ config, pkgs, lib, inputs, ... }:

{
  # Minimal Homebrew configuration - Only macOS-specific or unavailable packages

  homebrew = {
    enable = true;

    # === Homebrew Casks (GUI Applications) ===
    # Only keeping apps that are macOS-specific, proprietary, or not available in Nix
    casks = [
      # === macOS-Specific System Tools ===
      "1password"                   # Password manager (macOS Keychain integration)
      "onyx"                        # System maintenance (macOS-specific)
      "cleaner-one"                 # System cleaner (macOS-specific)
      "hiddenbar"                   # Menu bar organizer (macOS-specific)

      # === Development Tools ===
      "docker"                      # Docker Desktop (better macOS integration)

      # === Terminal & Development ===
      "ghostty"                     # GPU-accelerated terminal (native features)
      "cursor"                      # AI-powered code editor (macOS-optimized)

      # === Productivity & Workflow ===
      "raycast"                     # Spotlight replacement (macOS-optimized)
      "notion"                      # All-in-one workspace (native features)

      # === Communication & Social ===
      "discord"                     # Communication (better notifications)
      "spotify"                     # Music streaming (native features)

      # === Design & Creative Tools ===
      "figma"                       # Design tool (latest features, auto-updates)

      # === Proprietary/Commercial Software ===
      "microsoft-teams"             # Microsoft Teams (corporate features)
      "whatsapp"                    #

      # === Media Servers ===
      "plex-media-server"           # Media server (better integration via Homebrew)

      # === Communication ===
      "spark"                       # Email client (Mac-specific features)

      # === Browsers ===
      arc-browser         # Modern browser
      google-chrome       # Chrome browser
    ];

    # === Mac App Store Applications ===
    # Only keeping Apple ecosystem apps and those requiring App Store licensing
    masApps = {
      # === Apple Productivity Suite ===
      "Pages" = 409201541;           # Apple's word processor
      "Numbers" = 409203825;         # Apple's spreadsheet app
      "Keynote" = 409183694;         # Apple's presentation app

      # === Productivity ===
      "Trello" = 1278508951;         # Project management

      # === Design & Media (macOS-optimized) ===
      "Affinity Publisher" = 881418622;  # Desktop publishing
      "Affinity Designer" = 824171161;   # Vector design
      "Affinity Photo" = 824183456;      # Photo editing

      # === System Utilities (App Store exclusive) ===
      "DaisyDisk" = 411643860;       # Disk usage analyzer
      "The Unarchiver" = 425424353;  # Archive extractor (App Store version)
    };

    # === Homebrew Taps ===
    # Only keeping essential taps for specific tools
    taps = [
      "homebrew/services"            # Background services
    ];

    # === Command Line Tools (Brews) ===
    # Only keeping tools that are macOS-specific or problematic in Nix
    brews = [
      # === macOS-Specific CLI Tools ===
      "mas"                          # Mac App Store CLI (macOS-exclusive)
    ];

    # === Homebrew Management Settings ===
    onActivation = {
      cleanup = "zap";               # Remove unlisted apps and brews
      autoUpdate = true;             # Auto-update Homebrew
      upgrade = true;                # Auto-upgrade packages
    };

    # === Homebrew Global Settings ===
    global = {
      brewfile = true;               # Generate Brewfile
      lockfiles = true;              # Generate lock files
    };
  };

  # === Environment Variables for Homebrew ===
  environment.variables = {
    # Homebrew configuration
    HOMEBREW_CASK_OPTS = "--require-sha --no-quarantine";
    HOMEBREW_NO_ANALYTICS = "1";     # Disable analytics
    HOMEBREW_NO_INSECURE_REDIRECT = "1";  # Disable insecure redirects
    HOMEBREW_CASK_OPTS_NO_BINARIES = "1"; # Don't link binaries for casks
  };
}