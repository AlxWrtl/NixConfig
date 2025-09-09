{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # Homebrew package management configuration
  # GUI applications, macOS-specific tools, and proprietary software
  # CLI tools are managed through Nix in packages.nix and development.nix

  # ============================================================================
  # HOMEBREW CORE CONFIGURATION
  # ============================================================================

  homebrew = {
    enable = true;

    # === Global Cask Configuration ===
    caskArgs = {
      no_quarantine = true; # Disable quarantine warnings for all casks
    };

    # === Automatic Package Management ===
    onActivation = {
      cleanup = "zap"; # Remove packages and associated data not listed in configuration
      autoUpdate = true; # Update Homebrew itself during rebuild
      upgrade = true; # Upgrade outdated packages during rebuild
    };

    # === Global Homebrew Settings ===
    global = {
      brewfile = true; # Generate Brewfile for compatibility
    };

    # === Repository Taps ===
    taps = [
      # Using default taps - add custom taps here if needed
      # Example: "homebrew/cask-fonts"
    ];

    # ============================================================================
    # COMMAND LINE TOOLS (BREWS)
    # ============================================================================

    brews = [
      # === macOS-Specific CLI Tools ===
      "mas" # Mac App Store command-line interface
      "trash" # macOS-native trash utility for cleanup scripts

      # Note: Most CLI tools are managed through Nix for reproducibility
      # Only add tools here that are problematic in Nix or require macOS integration
    ];

    # ============================================================================
    # GUI APPLICATIONS (CASKS)
    # ============================================================================

    casks = [
      # === System Administration & Utilities ===
      {
        name = "1password";
        greedy = true;
      } # Password manager with Keychain integration
      {
        name = "onyx";
        greedy = true;
      } # macOS system maintenance and optimization
      {
        name = "jordanbaird-ice";
        greedy = true;
      } # Menu bar organizer (modern Hidden Bar alternative)
      {
        name = "logi-options+";
        greedy = true;
      } # Logitech device configuration
      # { name = "lunar"; greedy = true; }                                 # External display brightness control
      {
        name = "keka";
        greedy = true;
      } # File archiver with modern interface
      {
        name = "daisydisk";
        greedy = true;
      } # Visual disk usage analyzer
      {
        name = "fliqlo";
        greedy = true;
      } # Flickering-free screen saver

      # === Development & Programming ===
      {
        name = "docker-desktop";
        greedy = true;
      } # Docker containerization platform
      {
        name = "visual-studio-code";
        greedy = true;
      } # Microsoft's code editor with extensions
      {
        name = "cursor";
        greedy = true;
      } # AI-powered code editor
      {
        name = "chatgpt";
        greedy = true;
      } # OpenAI's chatbot

      # === Terminal & Command Line ===
      {
        name = "ghostty";
        greedy = true;
      } # GPU-accelerated terminal emulator

      # === Productivity & Workflow ===
      {
        name = "raycast";
        greedy = true;
      } # Spotlight replacement with plugins
      {
        name = "notion";
        greedy = true;
      } # All-in-one workspace and note-taking

      # === Design & Creative Tools ===
      {
        name = "figma";
        greedy = true;
      } # Collaborative design and prototyping

      # === Communication & Collaboration ===
      {
        name = "discord";
        greedy = true;
      } # Gaming and community communication
      {
        name = "microsoft-teams";
        greedy = true;
      } # Business communication and meetings
      {
        name = "whatsapp";
        greedy = true;
      } # Cross-platform messaging
      {
        name = "readdle-spark";
        greedy = true;
      } # Email client with smart features

      # === Web Browsers ===
      {
        name = "arc";
        greedy = true;
      } # Modern browser with unique features
      {
        name = "google-chrome";
        greedy = true;
      } # Google's web browser

      # === Media & Entertainment ===
      {
        name = "vlc";
        greedy = true;
      } # Universal media player
      # { name = "spotify"; greedy = true; }                               # Music streaming service
      {
        name = "plex-media-server";
        greedy = true;
      } # Personal media server
    ];

    # ============================================================================
    # MAC APP STORE APPLICATIONS
    # ============================================================================

    masApps = {
      # === Apple Productivity Suite ===
      "Pages" = 409201541; # Apple's word processor
      "Numbers" = 409203825; # Apple's spreadsheet application
      "Keynote" = 409183694; # Apple's presentation software

      # === Project Management ===
      "Trello" = 1278508951; # Visual project management boards

      # === System Utilities ===
      "DaisyDisk" = 411643860; # Disk usage visualization (if not using cask)
    };
  };

  # ============================================================================
  # HOMEBREW ENVIRONMENT CONFIGURATION
  # ============================================================================

  environment.variables = {
    # === Homebrew Core Settings ===
    HOMEBREW_NO_ANALYTICS = "1"; # Disable usage analytics
    HOMEBREW_NO_INSECURE_REDIRECT = "1"; # Prevent insecure redirects
    HOMEBREW_CASK_OPTS_NO_BINARIES = "1"; # Don't symlink cask binaries
    HOMEBREW_PREFIX = "/opt/homebrew"; # Homebrew installation prefix

    # === Mac App Store CLI Configuration ===
    MAS_NO_PROMPT = "1"; # Prevent interactive prompts during automation
  };

  # === System PATH Integration ===
  environment.systemPath = [
    "/opt/homebrew/bin" # Homebrew binaries
    "/usr/local/bin" # Legacy Homebrew path for compatibility
  ];
}
