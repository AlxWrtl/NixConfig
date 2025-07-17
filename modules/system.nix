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
    package = pkgs.nixVersions.latest;               # Use latest Nix version (2.29+ has security fixes)
    # package = pkgs.nixVersions.stable;             # Fallback to stable if needed

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
      # restrict-eval = true;                         # TODO: Enable after initial setup (causes flake fetch issues)

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

      # Security: limit extra trusted substituters
      extra-trusted-substituters = [];               # Empty by default for security

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
      tarball-ttl = 3600 * 24 * 7;                   # Cache tarballs for 7 days
    };

    # === Automatic Maintenance ===
    optimise.automatic = true;                        # Enable automatic store optimization and deduplication
    gc = {
      automatic = true;                               # Enable automatic garbage collection
      interval = { Weekday = 7; Hour = 3; Minute = 0; }; # Run weekly on Sunday at 3:00 AM (specific time)
      options = "--delete-older-than 21d --max-freed 10G"; # Keep 21 days, max 10GB freed per run
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
        # -- Sleep Timings --
        /usr/bin/pmset -a displaysleep 25               # Display sleep after 25 minutes
        /usr/bin/pmset -a sleep 45                      # System sleep after 45 minutes

        # -- Hibernate & Standby --
        /usr/bin/pmset -a hibernatemode 60              # Hybrid sleep (RAM + disk)
        /usr/bin/pmset -a standby 1                     # Enable standby mode
        /usr/bin/pmset -a standbydelay 1800             # Enter standby after 30 minutes
        /usr/bin/pmset -a autopoweroff 1                # Enable auto power off
        /usr/bin/pmset -a autopoweroffdelay 14400       # Auto power off after 4 hours

        # -- Power Saving Options --
        /usr/bin/pmset -a powernap 0                    # Disable Power Nap (saves battery)
        /usr/bin/pmset -a ttyskeepawake 0               # Allow sleep even with SSH sessions
        /usr/bin/pmset -a reducebright 1                # Reduce brightness before sleep
        /usr/bin/pmset -a halfdim 1                     # Dim screen before sleep

        # -- Logging --
        echo "Power optimization applied: $(date)" >> /var/log/power-optimization.log
      ''
    ];
    RunAtLoad = true;  # Apply settings at system startup
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
          # === Network performance tuning ===

          ## -- TCP Optimizations --
          /usr/sbin/sysctl -w net.inet.tcp.delayed_ack=2                  # Smart TCP ACK (moins de paquets inutiles)
          /usr/sbin/sysctl -w net.inet.tcp.sendspace=131072              # Buffer d'envoi TCP : 128KB
          /usr/sbin/sysctl -w net.inet.tcp.recvspace=131072              # Buffer de réception TCP : 128KB
          /usr/sbin/sysctl -w net.inet.tcp.slowstart_flightsize=16       # Slow start + agressif (bon réseau)
          /usr/sbin/sysctl -w net.inet.tcp.local_slowstart_flightsize=16 # Pareil pour connexions locales

          ## -- Sockets & Filesystem --
          /usr/sbin/sysctl -w kern.maxfiles=65536                        # Fichiers ouverts max global
          /usr/sbin/sysctl -w kern.maxfilesperproc=32768                # Par processus
          /usr/sbin/sysctl -w kern.ipc.somaxconn=1024                   # Connexions TCP entrantes en attente

          ## -- Logging --
          echo "Network optimization applied: $(date)" >> /var/log/network-optimization.log
        ''
      ];
      RunAtLoad = true;
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
          # Clear system RAM cache
        /usr/bin/purge && \

        # Clear logs older than 30 days
        /usr/bin/find /private/var/log -name "*.log" -mtime +30 -delete && \

        # Clear temporary files older than 7 days
        /usr/bin/find /private/tmp -mtime +7 -delete 2>/dev/null && \

        # Clear user cache
        /bin/rm -rf ~/Library/Caches/* && \

        # Run macOS maintenance scripts
        /usr/sbin/periodic daily weekly monthly && \

        # Log the cleanup
        echo "System cleanup completed: $(date)" >> /var/log/system-cleanup.log
      ''
      ];
      StartCalendarInterval = [
        { Weekday = 1; Hour = 10; Minute = 0; }           # Weekly on Monday at 10:00 AM
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
  # SYSTEM STATE VERSION
  # ============================================================================

  # === System State Version ===
  system.stateVersion = 5;                           # nix-darwin state version (don't change after initial setup)

}