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
          cd ${inputs.self} && \
          ${pkgs.nix}/bin/nix flake update && \
          echo "Flake updated automatically: $(date)" >> ~/.cache/nix-flake-update.log
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 14;
          Minute = 0;
        } # Weekly on Monday at 2:00 PM
      ];
      StandardOutPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/nix-flake-update.log";
      StandardErrorPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/nix-flake-update-error.log";
      RunAtLoad = false; # Don't run immediately on system boot
    };
  };

  # === Automatic Homebrew Updates ===
  # Update Homebrew metadata 2x/week with catch-up (saves 47MB on each rebuild)
  launchd.user.agents.homebrew-update = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Check last update time (catch-up if Mac was off)
          last_update_file="$HOME/.cache/homebrew-last-update"
          current_time=$(date +%s)

          # If no last update file, create it and run update
          if [ ! -f "$last_update_file" ]; then
            /opt/homebrew/bin/brew update && \
            echo "$current_time" > "$last_update_file" && \
            echo "$(date): Homebrew updated (first run)" >> ~/.cache/homebrew-update.log
            exit 0
          fi

          # Check if last update was more than 3 days ago (catch-up threshold)
          last_update=$(cat "$last_update_file")
          time_diff=$((current_time - last_update))
          three_days=$((3 * 24 * 60 * 60))

          if [ "$time_diff" -gt "$three_days" ]; then
            /opt/homebrew/bin/brew update && \
            echo "$current_time" > "$last_update_file" && \
            echo "$(date): Homebrew updated (catch-up after $((time_diff / 86400)) days)" >> ~/.cache/homebrew-update.log
          else
            echo "$(date): Homebrew update skipped (last update $((time_diff / 86400)) days ago)" >> ~/.cache/homebrew-update.log
          fi
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 2;
          Hour = 9;
          Minute = 0;
        } # Tuesday at 9:00 AM
        {
          Weekday = 4;
          Hour = 9;
          Minute = 0;
        } # Thursday at 9:00 AM
      ];
      StandardOutPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/homebrew-update.log";
      StandardErrorPath = "${config.users.users.${config.system.primaryUser}.home}/.cache/homebrew-update-error.log";
      RunAtLoad = true; # Run on login to catch-up missed updates
    };
  };

  # ============================================================================
  # SYSTEM PERFORMANCE OPTIMIZATION
  # ============================================================================

  # === Advanced Power Management ===
  # Configure optimal power settings for battery life and performance
  launchd.daemons.power-optimization = lib.mkIf config.nix-darwin.enableOptimizations (mkMaintenanceDaemon {
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
  });

  # === Network Performance Tuning ===
  # Optimize TCP/IP stack for better network performance and throughput
  launchd.daemons.network-optimization = lib.mkIf config.nix-darwin.enableOptimizations (mkMaintenanceDaemon {
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
  });

  # ============================================================================
  # SYSTEM STATE VERSION
  # ============================================================================

  # === System State Version ===
  system.stateVersion = 5; # nix-darwin state version (don't change after initial setup)

}
