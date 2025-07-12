{ config, pkgs, lib, inputs, ... }:

{
  # ============================================================================
  # SECURITY MODULE - 2025 BEST PRACTICES
  # ============================================================================
  # Comprehensive security configuration for nix-darwin systems
  # Includes vulnerability scanning, automated security updates, and hardening

  # ============================================================================
  # AUTOMATED SECURITY SCANNING
  # ============================================================================

  # === System-wide vulnerability scanning ===
  launchd.daemons.security-scan = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Create scan directory if it doesn't exist
          /bin/mkdir -p /var/log/security
          
          # Run vulnerability scan
          ${pkgs.vulnix}/bin/vulnix --system /var/run/current-system \
            --json /var/log/security/vulnix-scan.json \
            2>/var/log/security/vulnix-scan-error.log || true
          
          # Log scan completion
          echo "Security scan completed: $(date)" >> /var/log/security/vulnix-scan.log
          
          # Check for critical vulnerabilities (exit code indicates severity)
          CRITICAL_COUNT=$(${pkgs.jq}/bin/jq '[.[] | select(.severity == "critical")] | length' /var/log/security/vulnix-scan.json 2>/dev/null || echo "0")
          
          if [ "$CRITICAL_COUNT" -gt 0 ]; then
            echo "WARNING: $CRITICAL_COUNT critical vulnerabilities found!" >> /var/log/security/vulnix-scan.log
            # Could send notification here in the future
          fi
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 1; Hour = 8; Minute = 0; }   # Monday 8 AM
        { Weekday = 4; Hour = 8; Minute = 0; }   # Thursday 8 AM
      ];
      StandardOutPath = "/var/log/security/vulnix-scan.log";
      StandardErrorPath = "/var/log/security/vulnix-scan-error.log";
      RunAtLoad = false;
    };
  };

  # === Security update notifications ===
  launchd.daemons.security-update-check = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Create security log directory
          /bin/mkdir -p /var/log/security
          
          # Check for outdated packages in the system
          cd /Users/alx/.config/nix-darwin
          
          # Check if flake.lock is older than 7 days
          if [ -f flake.lock ]; then
            LOCK_AGE=$(echo "$(date +%s) - $(stat -f %m flake.lock)" | bc)
            WEEK_SECONDS=604800
            
            if [ "$LOCK_AGE" -gt "$WEEK_SECONDS" ]; then
              echo "$(date): flake.lock is older than 7 days - consider updating" >> /var/log/security/update-check.log
            fi
          fi
          
          # Log successful check
          echo "$(date): Security update check completed" >> /var/log/security/update-check.log
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 2; Hour = 9; Minute = 0; }   # Tuesday 9 AM
      ];
      StandardOutPath = "/var/log/security/update-check.log";
      StandardErrorPath = "/var/log/security/update-check-error.log";
      RunAtLoad = false;
    };
  };

  # ============================================================================
  # SYSTEM SECURITY HARDENING
  # ============================================================================

  # === Enhanced file system security ===
  launchd.daemons.filesystem-hardening = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Set secure permissions on sensitive directories
          /usr/bin/find /usr/local -type d -exec chmod 755 {} \; 2>/dev/null || true
          /usr/bin/find /opt -type d -exec chmod 755 {} \; 2>/dev/null || true
          
          # Secure Nix store permissions (already handled by Nix, but double-check)
          /bin/chmod 1775 /nix/store 2>/dev/null || true
          
          # Log hardening completion
          echo "Filesystem hardening completed: $(date)" >> /var/log/security/hardening.log
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 0; Hour = 5; Minute = 0; }   # Sunday 5 AM
      ];
      StandardOutPath = "/var/log/security/hardening.log";
      StandardErrorPath = "/var/log/security/hardening-error.log";
      RunAtLoad = true;  # Run on system boot
    };
  };

  # ============================================================================
  # SECURITY MONITORING
  # ============================================================================

  # === Log rotation for security logs ===
  launchd.daemons.security-log-rotation = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Rotate security logs if they get too large (>10MB)
          find /var/log/security -name "*.log" -size +10M -exec sh -c '
            for log do
              if [ -f "$log" ]; then
                cp "$log" "$log.old"
                echo "$(date): Log rotated" > "$log"
              fi
            done
          ' sh {} +
          
          # Clean up old logs (older than 30 days)
          find /var/log/security -name "*.log.old" -mtime +30 -delete
          
          echo "Log rotation completed: $(date)" >> /var/log/security/rotation.log
        ''
      ];
      StartCalendarInterval = [
        { Weekday = 0; Hour = 4; Minute = 30; }  # Sunday 4:30 AM
      ];
      StandardOutPath = "/var/log/security/rotation.log";
      StandardErrorPath = "/var/log/security/rotation-error.log";
      RunAtLoad = false;
    };
  };

  # ============================================================================
  # SECURITY UTILITIES
  # ============================================================================

  environment.systemPackages = with pkgs; [
    # Security scanning and analysis
    vulnix                        # CVE scanner for Nix packages
    
    # File integrity and encryption
    age                          # Modern encryption tool
    sops                         # Secrets management
    
    # Network security
    nmap                         # Network discovery and security auditing
    
    # System monitoring
    htop                         # Process monitoring
    # Note: iotop is Linux-only, macOS uses Activity Monitor or built-in tools
  ];

  # ============================================================================
  # SECURITY ALIASES
  # ============================================================================

  environment.shellAliases = {
    # Security scanning shortcuts
    "vulnscan" = "vulnix --system /var/run/current-system";
    "vulnscan-json" = "vulnix --system /var/run/current-system --json /tmp/vulnix-output.json";
    "security-logs" = "tail -f /var/log/security/*.log";
    
    # Quick security checks
    "check-perms" = "ls -la /nix/store | head -20";
    "check-security" = "cat /var/log/security/vulnix-scan.log | tail -10";
  };

  # ============================================================================
  # SECURITY ENVIRONMENT VARIABLES
  # ============================================================================

  environment.variables = {
    # Security-focused environment
    SECURITY_LOG_DIR = "/var/log/security";
    
    # Ensure secure defaults for tools
    GNUPGHOME = "$HOME/.config/gnupg";
    AGE_DIR = "$HOME/.config/age";
  };

}