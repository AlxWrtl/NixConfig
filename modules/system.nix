{ config, pkgs, lib, inputs, ... }:

{
  # Core nix-darwin system configuration
  # Note: UI/UX settings are in ui.nix, development tools in development.nix

  # ============================================================================
  # NIX PACKAGE MANAGER CONFIGURATION
  # ============================================================================

  nix = {
    # === Core Nix System Settings ===
    enable = true;                                    # Enable nix-darwin module management for services and integrations

    settings = {
      # === Modern Nix Features ===
      experimental-features = [
        "nix-command"
        "flakes"
        "ca-derivations"                              # Content-addressed derivations for enhanced security
        "fetch-closure"                               # Secure closure fetching
      ];

      # === 2025 Security Enhancements ===
      # Addresses CVE-2025-46415, CVE-2025-46416, CVE-2025-52991, CVE-2025-52992, CVE-2025-52993
      trusted-users = [ "root" "@admin" ];           # Explicitly limit trusted users
      allowed-users = [ "@wheel" "alx" ];            # Restrict allowed users to wheel group and primary user
      sandbox = true;                                 # Enable build sandboxing to isolate builds
      require-sigs = true;                            # Require signatures for all substituters

      # === Build Performance Optimization ===
      max-jobs = "auto";                              # Use all available CPU cores for parallel builds
      cores = 0;                                      # Use all cores per job (0 = auto-detect)
      builders-use-substitutes = true;                # Allow builders to use substitutes for better performance

      # === Enhanced Binary Cache Configuration ===
      # Reduces build times by downloading pre-built packages with security controls
      substituters = [
        "https://cache.nixos.org/"                    # Official NixOS binary cache
        "https://nix-community.cachix.org"            # Community packages cache
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];

      # === Network Security & Performance ===
      fallback = false;                               # Don't fallback to building if substitution fails (security)
      connect-timeout = 10;                           # Timeout for network connections (10 seconds)
      http-connections = 25;                          # Parallel HTTP connections for downloads
      download-attempts = 3;                          # Retry failed downloads up to 3 times
      log-lines = 25;                                 # Limit log lines for security and performance

      # === Store Management ===
      min-free = 1000000000;                          # Keep minimum 1GB free space (1 billion bytes)
      max-free = 5000000000;                          # Use maximum 5GB for store operations

    };

    # === Automatic Maintenance ===
    optimise.automatic = true;                        # Enable automatic store optimization
    gc = {
      automatic = true;                               # Enable automatic garbage collection
      interval = { Weekday = 7; Hour = 3; Minute = 0; }; # Run weekly on Sunday at 3:00 AM (specific time)
      options = "--delete-older-than 30d";           # Keep 30 days of generations (increased from 7d for safety)
    };
  };

  # ============================================================================
  # NIXPKGS PACKAGE CONFIGURATION
  # ============================================================================

  nixpkgs.config = {
    # === Package Permissions ===
    allowUnfree = lib.mkDefault true;                 # Allow proprietary packages (VS Code, Slack, etc.)
    allowBroken = false;                              # Prevent installation of known broken packages
    allowInsecure = false;                            # Prevent installation of packages with security vulnerabilities

    # === Package-Specific Overrides ===
    permittedInsecurePackages = [
      # Add specific packages here if needed for compatibility
      # Example: "package-name-version"
    ];
  };

  # ============================================================================
  # SYSTEM ENVIRONMENT & USER MANAGEMENT
  # ============================================================================

  # === Global Environment Variables ===
  environment.variables = {
    # === Editor Configuration ===
    EDITOR = "nvim";                                  # Default command-line editor
    VISUAL = "nvim";                                  # Default visual editor for GUI applications
    PAGER = "less";                                   # Default pager for command output

    # === XDG Base Directory Specification ===
    XDG_CONFIG_HOME = "$HOME/.config";                # User configuration files
    XDG_CACHE_HOME = "$HOME/.cache";                  # User cache files
    XDG_DATA_HOME = "$HOME/.local/share";             # User data files
  };

  # === Primary User Configuration ===
  system.primaryUser = "alx";                        # Primary user for homebrew and user-specific settings

  # ============================================================================
  # SECURITY & AUTHENTICATION
  # ============================================================================

  # === Touch ID Authentication ===
  security.pam.services.sudo_local.touchIdAuth = true; # Enable Touch ID for sudo authentication

  # ============================================================================
  # SYSTEM CONFIGURATION NOTES
  # ============================================================================
  #
  # UI/UX Configuration: All system.defaults settings are in ui.nix
  # This includes: dock, finder, trackpad, NSGlobalDomain, loginwindow, etc.
  #
  # Separation of Concerns:
  # - system.nix: Core Nix configuration, security, environment variables
  # - ui.nix: All macOS interface and system defaults
  # - development.nix: Development tools and environments
  # - shell.nix: Shell configuration and performance
  # - packages.nix: System packages and CLI tools

  # ============================================================================
  # SYSTEM SERVICES & DAEMONS
  # ============================================================================

  # === Launch Daemons ===
  # Custom system services can be defined here
  # Example:
  # launchd.daemons.myservice = {
  #   serviceConfig = {
  #     ProgramArguments = [ "/path/to/program" ];
  #     RunAtLoad = true;
  #   };
  # };

  # ============================================================================
  # SYSTEM MAINTENANCE & OPTIMIZATION
  # ============================================================================

  # === Log Rotation ===
  # macOS handles log rotation automatically, but custom settings can be added here

  # === Periodic Scripts ===
  # Custom maintenance scripts can be scheduled here
  # Example: cleanup scripts, backup automation, etc.

  # ============================================================================
  # COMPATIBILITY & INTEGRATION
  # ============================================================================

  # === Homebrew Integration ===
  # Primary user setting enables Homebrew integration in brew.nix

  # === Shell Integration ===
  # Shell configuration is handled in shell.nix

  # === Development Tool Integration ===
  # Development environments are configured in development.nix

  # ============================================================================
  # SYSTEM INFORMATION & DOCUMENTATION
  # ============================================================================

  # === Version Information ===
  system.stateVersion = 5;                           # nix-darwin state version (don't change after initial setup)

  # === System Description ===
  # This configuration provides:
  # - Optimized Nix package manager setup with binary caches
  # - Secure authentication with Touch ID
  # - Basic trackpad and system behavior configuration
  # - Automatic maintenance and garbage collection
  # - Foundation for modular nix-darwin configuration
  #
  # Extended Configuration:
  # - UI/UX settings → ui.nix
  # - Development tools → development.nix
  # - Shell configuration → shell.nix
  # - GUI applications → brew.nix
  # - Fonts → fonts.nix
}