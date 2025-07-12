{ config, pkgs, lib, inputs, ... }:

{
  # ============================================================================
  # CORE NIX-DARWIN SYSTEM CONFIGURATION
  # ============================================================================

  # ============================================================================
  # NIX PACKAGE MANAGER CONFIGURATION
  # ============================================================================

  nix = {
    # === Core Nix System Settings ===
    enable = true;                                    # Enable nix-darwin module management for services and integrations

    # === Nix Package Version Management ===
    # Options: pkgs.nixVersions.stable (2.28.4) | pkgs.nixVersions.latest (2.29.1) | pkgs.nixVersions.nix_2_30
    package = pkgs.nixVersions.stable;               # Use stable Nix version (currently 2.28.4 - secure)
    # package = pkgs.nixVersions.latest;             # Uncomment for bleeding edge (2.29.1)

    settings = {
      # === Modern Nix Features ===
      experimental-features = [
        "nix-command"                                 # Enable new CLI commands (nix build, nix run, etc.)
        "flakes"                                      # Enable Nix flakes for reproducible configurations
        "ca-derivations"                              # Content-addressed derivations for enhanced security
        "fetch-closure"                               # Secure closure fetching from trusted sources
      ];

      # === 2025 Security Enhancements ===
      # Addresses CVE-2025-46415, CVE-2025-46416, CVE-2025-52991, CVE-2025-52992, CVE-2025-52993
      trusted-users = [ "root" "@admin" ];           # Explicitly limit trusted users who can modify store
      allowed-users = [ "@wheel" "alx" ];            # Restrict allowed users to wheel group and primary user
      sandbox = true;                                 # Enable build sandboxing to isolate builds from system
      require-sigs = true;                            # Require signatures for all substituters (security)

      # === Build Performance Optimization ===
      max-jobs = "auto";                              # Use all available CPU cores for parallel builds
      cores = 0;                                      # Use all cores per job (0 = auto-detect)
      builders-use-substitutes = true;                # Allow builders to use substitutes for better performance

      # === Enhanced Binary Cache Configuration ===
      # Reduces build times by downloading pre-built packages with security controls
      substituters = [
        "https://cache.nixos.org/"                    # Official NixOS binary cache (primary)
        "https://nix-community.cachix.org"            # Community packages cache (secondary)
      ];

      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="     # Official NixOS cache key
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs=" # Community cache key
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
    optimise.automatic = true;                        # Enable automatic store optimization and deduplication
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
    XDG_CONFIG_HOME = "$HOME/.config";                # User configuration files location
    XDG_CACHE_HOME = "$HOME/.cache";                  # User cache files location
    XDG_DATA_HOME = "$HOME/.local/share";             # User data files location
  };

  # === Primary User Configuration ===
  system.primaryUser = "alx";                        # Primary user for homebrew and user-specific settings

  # ============================================================================
  # SECURITY & AUTHENTICATION
  # ============================================================================

  # === Touch ID Authentication ===
  security.pam.services.sudo_local.touchIdAuth = true; # Enable Touch ID for sudo authentication

  # ============================================================================
  # AUTOMATED SYSTEM MAINTENANCE
  # ============================================================================

  # === Automatic Flake Updates ===
  # Keep system packages and Nix version current
  launchd.user.agents.nix-flake-update = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          cd /Users/alx/.config/nix-darwin && \
          ${pkgs.nix}/bin/nix flake update && \
          echo "Flake updated automatically: $(date)" >> ~/.cache/nix-flake-update.log
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 1; Hour = 9; Minute = 0; }             # Weekly on Monday at 9:00 AM
      ];
      StandardOutPath = "/Users/alx/.cache/nix-flake-update.log";
      StandardErrorPath = "/Users/alx/.cache/nix-flake-update-error.log";
      RunAtLoad = false;                              # Don't run immediately on system boot
    };
  };

  # ============================================================================
  # SYSTEM PERFORMANCE OPTIMIZATION
  # ============================================================================

  # === Advanced Power Management ===
  # Configure optimal power settings for battery life and performance
  launchd.daemons.power-optimization = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Advanced power management configuration
          /usr/bin/pmset -a powernap 0                    # Disable Power Nap globally (saves battery)
          /usr/bin/pmset -a ttyskeepawake 0               # Allow sleep with SSH sessions active
          /usr/bin/pmset -a displaysleep 10               # Display sleep after 10 minutes
          /usr/bin/pmset -a sleep 30                      # System sleep after 30 minutes
          /usr/bin/pmset -a hibernatemode 25              # Hybrid sleep mode (RAM + disk)
          /usr/bin/pmset -a autopoweroff 1                # Enable auto power off after extended sleep
          /usr/bin/pmset -a autopoweroffdelay 28800       # Auto power off after 8 hours (28800 seconds)
          /usr/bin/pmset -a standbydelay 86400            # Standby mode after 24 hours (86400 seconds)
          /usr/bin/pmset -a standby 1                     # Enable standby mode for better battery life
          /usr/bin/pmset -a reducebright 1                # Reduce brightness before sleep
          /usr/bin/pmset -a halfdim 1                     # Dim display before sleep
          echo "Power optimization applied: $(date)" >> /var/log/power-optimization.log
        ''
      ];
      RunAtLoad = true;                               # Apply settings immediately on system boot
      StandardOutPath = "/var/log/power-optimization.log";
      StandardErrorPath = "/var/log/power-optimization-error.log";
    };
  };

  # === Network Performance Tuning ===
  # Optimize TCP/IP stack for better network performance and throughput
  launchd.daemons.network-optimization = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Network performance tuning
          /usr/sbin/sysctl -w net.inet.tcp.delayed_ack=2           # Optimize TCP acknowledgments
          /usr/sbin/sysctl -w net.inet.tcp.sendspace=131072       # Increase TCP send buffer to 128KB
          /usr/sbin/sysctl -w net.inet.tcp.recvspace=131072       # Increase TCP receive buffer to 128KB
          /usr/sbin/sysctl -w net.inet.tcp.slowstart_flightsize=20    # Optimize TCP slow start algorithm
          /usr/sbin/sysctl -w net.inet.tcp.local_slowstart_flightsize=20  # Optimize local TCP connections
          /usr/sbin/sysctl -w kern.maxfiles=65536                 # Increase maximum open files limit
          /usr/sbin/sysctl -w kern.maxfilesperproc=32768          # Increase max files per process
          /usr/sbin/sysctl -w kern.ipc.somaxconn=1024             # Increase socket connection queue size
          echo "Network optimization applied: $(date)" >> /var/log/network-optimization.log
        ''
      ];
      RunAtLoad = true;                               # Apply settings immediately on system boot
      StandardOutPath = "/var/log/network-optimization.log";
      StandardErrorPath = "/var/log/network-optimization-error.log";
    };
  };

  # === Storage Optimization & Cleanup ===
  # Regular cleanup of system caches and temporary files
  launchd.daemons.system-cleanup = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Clear system caches and temporary files
          /usr/bin/purge                                                    && \
          /bin/rm -rf /private/var/folders/*/0/safarihistory*              && \
          /bin/rm -rf /private/var/folders/*/C/com.apple.Safari/CloudTabs  && \
          /usr/bin/find /private/var/log -name "*.log" -mtime +30 -delete  && \
          /usr/bin/find /private/tmp -mtime +7 -delete 2>/dev/null         && \
          /usr/sbin/periodic daily weekly monthly                          && \
          echo "System cleanup completed: $(date)" >> /var/log/system-cleanup.log
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 0; Hour = 4; Minute = 0; }           # Weekly on Sunday at 4:00 AM
      ];
      StandardOutPath = "/var/log/system-cleanup.log";
      StandardErrorPath = "/var/log/system-cleanup-error.log";
      RunAtLoad = false;                              # Don't run on system boot
    };
  };

  # === Spotlight Indexing Optimization ===
  # Periodic Spotlight reindexing for optimal search performance
  launchd.daemons.spotlight-optimize = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Reindex Spotlight for optimal performance
          /usr/bin/mdutil -a -i off                                        && \
          /bin/sleep 60                                                     && \
          /usr/bin/mdutil -a -i on                                         && \
          /usr/bin/mdutil -a -E                                            && \
          echo "Spotlight optimization completed: $(date)" >> /var/log/spotlight-optimize.log
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 6; Hour = 3; Minute = 0; }           # Weekly on Saturday at 3:00 AM
      ];
      StandardOutPath = "/var/log/spotlight-optimize.log";
      StandardErrorPath = "/var/log/spotlight-optimize-error.log";
      RunAtLoad = false;                              # Don't run on system boot
    };
  };

  # === Disk Space Management ===
  # Automated disk cleanup and optimization tasks
  launchd.daemons.disk-cleanup = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Automated disk cleanup and optimization
          /usr/bin/du -sh /private/var/folders/*/T/* 2>/dev/null | /usr/bin/sort -hr | /usr/bin/head -10 && \
          /usr/bin/find /private/var/folders/*/T -name "*" -mtime +3 -delete 2>/dev/null && \
          /usr/sbin/diskutil repairPermissions /                           && \
          /usr/sbin/diskutil verifyVolume /                                 && \
          /usr/bin/tmutil thinlocalsnapshots / 10000000000 4               && \
          echo "Disk cleanup completed: $(date)" >> /var/log/disk-cleanup.log
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 2; Hour = 3; Minute = 0; }           # Weekly on Tuesday at 3:00 AM
      ];
      StandardOutPath = "/var/log/disk-cleanup.log";
      StandardErrorPath = "/var/log/disk-cleanup-error.log";
      RunAtLoad = false;                              # Don't run on system boot
    };
  };

  # ============================================================================
  # SYSTEM INTEGRATION & COMPATIBILITY
  # ============================================================================

  # === Module Integration Notes ===
  # This configuration integrates with other modules:
  # - ui.nix: All macOS interface and system defaults (dock, finder, trackpad, etc.)
  # - development.nix: Development tools and programming environments
  # - shell.nix: Shell configuration, aliases, and command-line tools
  # - packages.nix: System packages and CLI utilities
  # - brew.nix: GUI applications managed via Homebrew
  # - fonts.nix: Font management and typography settings

  # === Homebrew Integration ===
  # Primary user setting enables Homebrew integration in brew.nix

  # === System State Version ===
  system.stateVersion = 5;                           # nix-darwin state version (don't change after initial setup)

}