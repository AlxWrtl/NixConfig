{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

let
  # Import constants & helpers
  systemConstants = import ./constants.nix;
  mkMaintenanceDaemon = import ./launchd-helpers.nix;
in

{
  # ============================================================================
  # CORE NIX-DARWIN SYSTEM CONFIGURATION
  # ============================================================================

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
    };

    # === Automatic Maintenance ===
    optimise.automatic = true; # Enable automatic store optimization and deduplication
    gc = {
      automatic = true; # Enable automatic garbage collection
      interval = {
        Weekday = 7;
        Hour = 3;
        Minute = 0;
      }; # Run weekly on Sunday at 3:00 AM (specific time)
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
  # SYSTEM ENVIRONMENT & USER MANAGEMENT
  # ============================================================================

  # === Global Environment Variables ===
  environment.variables = {
    # === Editor Configuration ===
    EDITOR = "nvim"; # Default command-line editor
    VISUAL = "nvim"; # Default visual editor for GUI applications
    PAGER = "less"; # Default pager for command output

    # === XDG Base Directory Specification ===
    XDG_CONFIG_HOME = "$HOME/.config"; # User configuration files location
    XDG_CACHE_HOME = "$HOME/.cache"; # User cache files location
    XDG_DATA_HOME = "$HOME/.local/share"; # User data files location
  };

  # === Primary User Configuration ===
  system.primaryUser = "alx"; # Primary user for homebrew and user-specific settings

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
        {
          Weekday = 1;
          Hour = 9;
          Minute = 0;
        } # Weekly on Monday at 9:00 AM
      ];
      StandardOutPath = "/Users/alx/.cache/nix-flake-update.log";
      StandardErrorPath = "/Users/alx/.cache/nix-flake-update-error.log";
      RunAtLoad = false; # Don't run immediately on system boot
    };
  };

  # === Automatic Homebrew Updates ===
  # Update Homebrew metadata weekly (saves 47MB on each rebuild)
  launchd.user.agents.homebrew-update = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          /opt/homebrew/bin/brew update && \
          echo "Homebrew updated automatically: $(date)" >> ~/.cache/homebrew-update.log
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 9;
          Minute = 15;
        } # Weekly on Monday at 9:15 AM (after flake update)
      ];
      StandardOutPath = "/Users/alx/.cache/homebrew-update.log";
      StandardErrorPath = "/Users/alx/.cache/homebrew-update-error.log";
      RunAtLoad = false;
    };
  };

  # ============================================================================
  # SYSTEM PERFORMANCE OPTIMIZATION
  # ============================================================================

  # === Advanced Power Management ===
  # Configure optimal power settings for battery life and performance
  launchd.daemons.power-optimization = mkMaintenanceDaemon {
    name = "power-optimization";
    runAtLoad = true;
    script = ''
      # -- Sleep Timings --
      /usr/bin/pmset -a displaysleep ${toString systemConstants.displaySleepMinutes}
      /usr/bin/pmset -a sleep ${toString systemConstants.systemSleepMinutes}

      # -- Sleep Behavior (no deep sleep) --
      /usr/bin/pmset -a hibernatemode 3               # Normal sleep (RAM powered + safe disk copy)
      /usr/bin/pmset -a standby 0                     # Disable standby (prevents deep sleep)
      /usr/bin/pmset -a autopoweroff 0                # Disable auto power off (prevents deep sleep)
      /usr/bin/pmset -a standbydelay 0                # No standby delay
      /usr/bin/pmset -a autopoweroffdelay 0           # No auto power off delay
      /usr/bin/pmset -a destroyfvkeyonstandby 0       # Keep FileVault key in RAM (avoid forced hibernate)

      # -- Power Saving Options --
      /usr/bin/pmset -a powernap 0                    # Disable Power Nap (saves battery)
      /usr/bin/pmset -a ttyskeepawake 0               # Allow sleep even with SSH sessions
      /usr/bin/pmset -a reducebright 1                # Reduce brightness before sleep
      /usr/bin/pmset -a halfdim 1                     # Dim screen before sleep

      # -- Logging --
      echo "Power optimization applied: $(date)" >> /var/log/power-optimization.log
    '';
  };

  # === Network Performance Tuning ===
  # Optimize TCP/IP stack for better network performance and throughput
  launchd.daemons.network-optimization = mkMaintenanceDaemon {
    name = "network-optimization";
    runAtLoad = true;
    script = ''
      # === Network performance tuning ===

      ## -- TCP Optimizations --
      /usr/sbin/sysctl -w net.inet.tcp.delayed_ack=2                  # Smart TCP ACK (moins de paquets inutiles)
      /usr/sbin/sysctl -w net.inet.tcp.sendspace=131072              # Buffer d'envoi TCP : 128KB
      /usr/sbin/sysctl -w net.inet.tcp.recvspace=131072              # Buffer de réception TCP : 128KB
      /usr/sbin/sysctl -w net.inet.tcp.slowstart_flightsize=${toString systemConstants.tcpSlowStartFlightSize}
      /usr/sbin/sysctl -w net.inet.tcp.local_slowstart_flightsize=${toString systemConstants.tcpSlowStartFlightSize}

      ## -- Sockets & Filesystem --
      /usr/sbin/sysctl -w kern.maxfiles=${toString systemConstants.maxOpenFiles}
      /usr/sbin/sysctl -w kern.maxfilesperproc=${toString systemConstants.maxFilesPerProc}
      /usr/sbin/sysctl -w kern.ipc.somaxconn=1024                   # Connexions TCP entrantes en attente

      ## -- Logging --
      echo "Network optimization applied: $(date)" >> /var/log/network-optimization.log
    '';
  };

  # === Storage Optimization & Cleanup ===
  # Regular cleanup of system caches and temporary files
  launchd.daemons.system-cleanup = mkMaintenanceDaemon {
    name = "system-cleanup";
    schedule = [
      {
        Weekday = 1;
        Hour = 10;
        Minute = 0;
      } # Weekly on Monday at 10:00 AM
    ];
    script = ''
      # Clear logs older than ${toString systemConstants.logRetentionDays} days
      /usr/bin/find /private/var/log -name "*.log" -mtime +${toString systemConstants.logRetentionDays} -delete && \

      # Clear temporary files older than ${toString systemConstants.tempFileRetentionDays} days
      /usr/bin/find /private/tmp -mtime +${toString systemConstants.tempFileRetentionDays} -delete 2>/dev/null && \

      # Clear user cache (preserve critical app data)
      /usr/bin/find ~/Library/Caches -type f -mtime +${toString systemConstants.cacheFileRetentionDays} -delete 2>/dev/null && \

      # Run macOS maintenance scripts
      /usr/sbin/periodic daily weekly monthly && \

      # Log the cleanup
      echo "System cleanup completed: $(date)" >> /var/log/system-cleanup.log
    '';
  };

  # === Spotlight Indexing Optimization ===
  # Only reindex if Spotlight is corrupted (check first)
  launchd.daemons.spotlight-optimize = mkMaintenanceDaemon {
    name = "spotlight-optimize";
    schedule = [
      {
        Weekday = 6;
        Hour = 3;
        Minute = 0;
      } # Weekly on Saturday at 3:00 AM
    ];
    script = ''
      if /usr/bin/mdutil -s / | grep -q "disabled\\|Error"; then
        /usr/bin/mdutil -a -i off && \
        /bin/sleep 10 && \
        /usr/bin/mdutil -a -i on && \
        echo "Spotlight reindexed due to corruption: $(date)" >> /var/log/spotlight-optimize.log
      else
        echo "Spotlight healthy, skipping reindex: $(date)" >> /var/log/spotlight-optimize.log
      fi
    '';
  };

  # === Disk Space Management ===
  # Automated disk cleanup and optimization tasks
  launchd.daemons.disk-cleanup = mkMaintenanceDaemon {
    name = "disk-cleanup";
    schedule = [
      {
        Weekday = 2;
        Hour = 3;
        Minute = 0;
      } # Weekly on Tuesday at 3:00 AM
    ];
    script = ''
      # Automated disk cleanup and optimization
      /usr/bin/du -sh /private/var/folders/*/T/* 2>/dev/null | /usr/bin/sort -hr | /usr/bin/head -10 && \
      /usr/bin/find /private/var/folders/*/T -name "*" -mtime +3 -delete 2>/dev/null && \
      /usr/sbin/diskutil verifyVolume /                                 && \
      /usr/bin/tmutil thinlocalsnapshots / 10000000000 4               && \
      echo "Disk cleanup completed: $(date)" >> /var/log/disk-cleanup.log
    '';
  };

  # === Pre-GC Rollback Safety Check ===
  # Verify system can boot to previous generation before garbage collection
  launchd.daemons.pre-gc-rollback-test = mkMaintenanceDaemon {
    name = "pre-gc-rollback-test";
    schedule = [
      {
        Weekday = 7;
        Hour = 2;
        Minute = 30;
      } # Sunday 2:30 AM (30min before GC)
    ];
    script = ''
      # Check if we have at least 2 generations to rollback to
      gen_count=$(${pkgs.nix}/bin/nix-env --list-generations --profile /nix/var/nix/profiles/system | wc -l)

      if [ "$gen_count" -lt 2 ]; then
        echo "$(date): WARNING - Only $gen_count generation(s) available. Skipping rollback test." >> /var/log/pre-gc-rollback-test.log
        exit 0
      fi

      # Get current generation number
      current_gen=$(${pkgs.nix}/bin/nix-env --list-generations --profile /nix/var/nix/profiles/system | grep '(current)' | awk '{print $1}')

      # Get previous generation number
      prev_gen=$((current_gen - 1))

      # Resolve previous generation path via profile symlink
      prev_path=$(readlink "/nix/var/nix/profiles/system-$prev_gen-link" 2>/dev/null)

      if [ -z "$prev_path" ] || [ ! -e "$prev_path" ]; then
        echo "$(date): ERROR - Previous generation $prev_gen path not found or invalid" >> /var/log/pre-gc-rollback-test.log
        exit 1
      fi

      # Test that previous generation has required boot files
      if [ ! -f "$prev_path/activate" ]; then
        echo "$(date): ERROR - Previous generation $prev_gen missing activate script" >> /var/log/pre-gc-rollback-test.log
        exit 1
      fi

      # Log success
      echo "$(date): SUCCESS - Rollback test passed. Current: gen $current_gen, Rollback: gen $prev_gen at $prev_path" >> /var/log/pre-gc-rollback-test.log

      # Notify user of successful pre-GC safety check
      /usr/bin/osascript -e "display notification \"Rollback safety verified. GC scheduled in 30min.\" with title \"✅ Pre-GC Check\" sound name \"Glass\"" 2>/dev/null || true
    '';
  };

  # ============================================================================
  # SYSTEM STATE VERSION
  # ============================================================================

  # === System State Version ===
  system.stateVersion = 5; # nix-darwin state version (don't change after initial setup)

}
