{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  systemConstants = import ./constants.nix;
in

{
  # ============================================================================
  # NIX PACKAGE MANAGER CONFIGURATION
  # ============================================================================

  nix = {
    # === Core Nix System Settings ===
    enable = true; # Enable nix-darwin module management for services and integrations

    # === Nix Package Version Management ===
    # Options: pkgs.nixVersions.stable (2.28.4) | pkgs.nixVersions.latest (2.29.1) | pkgs.nixVersions.nix_2_30
    package = pkgs.nixVersions.latest; # Use latest Nix version (2.29+ has security fixes)
    # package = pkgs.nixVersions.stable;             # Fallback to stable if needed

    settings = {
      # === Modern Nix Features ===
      experimental-features = [
        "nix-command" # Enable new CLI commands (nix build, nix run, etc.)
        "flakes" # Enable Nix flakes for reproducible configurations
        "ca-derivations" # Content-addressed derivations for enhanced security
        "fetch-closure" # Secure closure fetching from trusted sources
      ];

      # === 2025 Security Enhancements ===
      # Addresses CVE-2025-46415, CVE-2025-46416, CVE-2025-52991, CVE-2025-52992, CVE-2025-52993
      trusted-users = [
        "root"
        "@admin"
      ]; # Explicitly limit trusted users who can modify store
      allowed-users = [
        "@wheel"
        "alx"
      ]; # Restrict allowed users to wheel group and primary user
      sandbox = true; # Enable build sandboxing to isolate builds from system
      require-sigs = true; # Require signatures for all substituters (security)
      # restrict-eval = false;                        # INCOMPATIBLE with flakes (blocks dynamic GitHub API calls, redirects, NAR fetching)
      # Security provided by: sandbox, require-sigs, trusted-users, allowed-users

      # === Build Performance Optimization ===
      max-jobs = "auto"; # Use all available CPU cores for parallel builds
      cores = 0; # Use all cores per job (0 = auto-detect)
      builders-use-substitutes = true; # Allow builders to use substitutes for better performance

      # === Enhanced Binary Cache Configuration ===
      # Reduces build times by downloading pre-built packages with security controls
      substituters = [
        "https://cache.nixos.org/" # Official NixOS binary cache (primary)
        "https://nix-community.cachix.org" # Community packages cache (secondary)
      ];

      # Security: limit extra trusted substituters
      extra-trusted-substituters = [ ]; # Empty by default for security

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=" # Official NixOS cache key
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" # Community cache key
      ];

      # === Network Security & Performance ===
      fallback = false; # Don't fallback to building if substitution fails (security)
      connect-timeout = 10; # Timeout for network connections (10 seconds)
      http-connections = 25; # Parallel HTTP connections for downloads
      download-attempts = 3; # Retry failed downloads up to 3 times
      log-lines = 25; # Limit log lines for security and performance

      # === Store Management ===
      min-free = 1000000000; # Keep minimum 1GB free space (1 billion bytes)
      max-free = 5000000000; # Use maximum 5GB for store operations
      tarball-ttl = 3600 * 24 * 7; # Cache tarballs for 7 days
      eval-cache = true; # Cache evaluation results for faster rebuilds
    };

    # === Automatic Maintenance ===
    optimise.automatic = true; # Enable automatic store optimization and deduplication
    gc = {
      automatic = true; # Enable automatic garbage collection
      interval = {
        Weekday = 7;
        Hour = 10;
        Minute = 0;
      }; # Run weekly on Sunday at 10:00 AM (daytime, after rollback test)
      options = "--delete-older-than ${toString systemConstants.gcRetentionDays}d --max-freed ${systemConstants.gcMaxFreed}";
    };
  };

  # ============================================================================
  # NIXPKGS PACKAGE CONFIGURATION
  # ============================================================================

  nixpkgs.config = {
    # === Package Permissions ===
    allowUnfree = lib.mkDefault true; # Allow proprietary packages (VS Code, Slack, etc.)
    allowBroken = false; # Prevent installation of known broken packages
    allowInsecure = false; # Prevent installation of packages with security vulnerabilities

    # === Package-Specific Overrides ===
    permittedInsecurePackages = [
      # Add specific packages here if needed for compatibility
      # Example: "package-name-version"
    ];
  };

  # ============================================================================
  # SYSTEM STATE VERSION
  # ============================================================================

  system.stateVersion = 5; # nix-darwin state version (don't change after initial setup)
}
