{ config, pkgs, lib, inputs, ... }:

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
      no_quarantine = true;                    # Disable quarantine warnings for all casks
    };

    # === Automatic Package Management ===
    onActivation = {
      cleanup = "uninstall";                  # Remove packages not listed in configuration
      autoUpdate = true;                      # Update Homebrew itself during rebuild
      upgrade = true;                         # Upgrade outdated packages during rebuild
    };

    # === Global Homebrew Settings ===
    global = {
      brewfile = true;                        # Generate Brewfile for compatibility
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
      "mas"                                   # Mac App Store command-line interface
      
      # Note: Most CLI tools are managed through Nix for reproducibility
      # Only add tools here that are problematic in Nix or require macOS integration
    ];

    # ============================================================================
    # GUI APPLICATIONS (CASKS)
    # ============================================================================
    
    casks = [
      # === System Administration & Utilities ===
      "1password"                             # Password manager with Keychain integration
      "onyx"                                  # macOS system maintenance and optimization
      "jordanbaird-ice"                       # Menu bar organizer (modern Hidden Bar alternative)
      "logi-options+"                         # Logitech device configuration
      "lunar"                                 # External display brightness control
      "keka"                                  # File archiver with modern interface
      "daisydisk"                             # Visual disk usage analyzer

      # === Development & Programming ===
      "docker-desktop"                        # Docker containerization platform
      "visual-studio-code"                    # Microsoft's code editor with extensions
      "cursor"                                # AI-powered code editor
      "android-studio"                        # Android development environment
      "ollama-app"                            # Local LLM management interface

      # === Terminal & Command Line ===
      "ghostty"                               # GPU-accelerated terminal emulator

      # === Productivity & Workflow ===
      "raycast"                               # Spotlight replacement with plugins
      "notion"                                # All-in-one workspace and note-taking

      # === Design & Creative Tools ===
      "figma"                                 # Collaborative design and prototyping

      # === Communication & Collaboration ===
      "discord"                               # Gaming and community communication
      "microsoft-teams"                       # Business communication and meetings
      "whatsapp"                              # Cross-platform messaging
      "readdle-spark"                         # Email client with smart features

      # === Web Browsers ===
      "arc"                                   # Modern browser with unique features
      "google-chrome"                         # Google's web browser

      # === Media & Entertainment ===
      "vlc"                                   # Universal media player
      "spotify"                               # Music streaming service
      "plex-media-server"                     # Personal media server
    ];

    # ============================================================================
    # MAC APP STORE APPLICATIONS
    # ============================================================================
    
    masApps = {
      # === Apple Productivity Suite ===
      "Pages" = 409201541;                    # Apple's word processor
      "Numbers" = 409203825;                  # Apple's spreadsheet application
      "Keynote" = 409183694;                  # Apple's presentation software

      # === Project Management ===
      "Trello" = 1278508951;                  # Visual project management boards

      # === System Utilities ===
      "DaisyDisk" = 411643860;                # Disk usage visualization (if not using cask)
    };
  };

  # ============================================================================
  # HOMEBREW ENVIRONMENT CONFIGURATION
  # ============================================================================
  
  environment.variables = {
    # === Homebrew Core Settings ===
    HOMEBREW_NO_ANALYTICS = "1";             # Disable usage analytics
    HOMEBREW_NO_INSECURE_REDIRECT = "1";     # Prevent insecure redirects
    HOMEBREW_CASK_OPTS_NO_BINARIES = "1";    # Don't symlink cask binaries
    HOMEBREW_PREFIX = "/opt/homebrew";        # Homebrew installation prefix

    # === Mac App Store CLI Configuration ===
    MAS_NO_PROMPT = "1";                      # Prevent interactive prompts during automation
  };

  # === System PATH Integration ===
  environment.systemPath = [ 
    "/opt/homebrew/bin"                       # Homebrew binaries
    "/usr/local/bin"                          # Legacy Homebrew path for compatibility
  ];

  # ============================================================================
  # PACKAGE MANAGEMENT STRATEGY NOTES
  # ============================================================================
  # 
  # Package Distribution Guidelines:
  # - GUI applications → Homebrew casks (this file)
  # - macOS-specific tools → Homebrew casks or brews
  # - Proprietary/commercial software → Homebrew casks
  # - CLI development tools → Nix packages (development.nix)
  # - System utilities → Nix packages (packages.nix)
  # - Language libraries → Native package managers (npm, pip, etc.)
  #
  # Advantages of Homebrew for GUI apps:
  # - Better macOS integration and native features
  # - Automatic updates and security patches
  # - App Store distribution for licensed software
  # - Superior notarization and Gatekeeper compatibility
  #
  # Maintenance:
  # - Automatic cleanup removes orphaned packages
  # - Regular updates ensure security patches
  # - Use `brew cleanup --prune=all` for manual cleanup
}