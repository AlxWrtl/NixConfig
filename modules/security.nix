{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # ============================================================================
  # SECURITY MODULE - 2025 BEST PRACTICES
  # ============================================================================
  # Comprehensive security configuration for nix-darwin systems
  # Includes vulnerability scanning, automated security updates, and hardening

  # ============================================================================
  # AUTOMATED SECURITY SCANNING
  # ============================================================================

  # === Automated Security Vulnerability Scanning ===
  launchd.daemons.security-vulnerability-scan = {
    serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          # Check last scan time (catch-up if Mac was off)
          last_scan_file="/var/log/security/vulnix-last-scan"
          current_time=$(date +%s)

          # Ensure log directory exists
          mkdir -p /var/log/security

          # If no last scan file, create it and run scan
          if [ ! -f "$last_scan_file" ]; then
            run_scan=true
          else
            # Check if last scan was more than 4 days ago (catch-up threshold)
            last_scan=$(cat "$last_scan_file" 2>/dev/null || echo "0")
            time_diff=$((current_time - last_scan))
            four_days=$((4 * 24 * 60 * 60))

            if [ "$time_diff" -gt "$four_days" ]; then
              run_scan=true
            else
              run_scan=false
              echo "$(date): CVE scan skipped (last scan $((time_diff / 86400)) days ago)" >> /var/log/security/vulnix-scan.log
            fi
          fi

          # Run scan if needed
          if [ "$run_scan" = "true" ]; then
            # Run vulnix scan and save results (warnings to stderr, JSON to file)
            ${pkgs.vulnix}/bin/vulnix --system /var/run/current-system --json 2>/var/log/security/vulnix-scan-error.log > /var/log/security/vulnix-scan.json || true

            # Update last scan timestamp
            echo "$current_time" > "$last_scan_file"

            # Parse results and notify if CVEs found
            if [ -f /var/log/security/vulnix-scan.json ]; then
              # Count packages with CVEs (grep "affected_by" occurrences)
              cve_count=$(/usr/bin/grep -c '"affected_by"' /var/log/security/vulnix-scan.json 2>/dev/null || echo "0")

              if [ "$cve_count" -gt 0 ]; then
                # Send macOS notification
                /usr/bin/osascript -e "display notification \"Found $cve_count package(s) with CVEs. Check /var/log/security/vulnix-scan.json\" with title \"🔒 Security Alert\" sound name \"Basso\"" || true

                # Log critical finding with details
                echo "$(date): ALERT - $cve_count package(s) affected by CVEs" >> /var/log/security/vulnix-alerts.log

                # Extract top 5 critical CVEs (CVSS >= 7.0)
                ${pkgs.jq}/bin/jq -r '.[] | select(.cvssv3_basescore | to_entries | any(.value >= 7.0)) | .name + " - " + (.affected_by | join(", "))' /var/log/security/vulnix-scan.json 2>/dev/null | head -5 >> /var/log/security/vulnix-alerts.log || true
              else
                echo "$(date): No CVEs detected" >> /var/log/security/vulnix-scan.log
              fi
            fi
          fi
        ''
      ];
      StartCalendarInterval = [
        {
          Weekday = 1;
          Hour = 10;
          Minute = 0;
        } # Monday 10 AM
        {
          Weekday = 4;
          Hour = 10;
          Minute = 0;
        } # Thursday 10 AM
      ];
      StandardOutPath = "/var/log/security/vulnix-scan.log";
      StandardErrorPath = "/var/log/security/vulnix-scan-error.log";
      RunAtLoad = true; # Run on boot to catch-up missed scans
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
        {
          Weekday = 2;
          Hour = 9;
          Minute = 0;
        } # Tuesday 9 AM
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
        {
          Weekday = 0;
          Hour = 5;
          Minute = 0;
        } # Sunday 5 AM
      ];
      StandardOutPath = "/var/log/security/hardening.log";
      StandardErrorPath = "/var/log/security/hardening-error.log";
      RunAtLoad = true; # Run on system boot
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
        {
          Weekday = 0;
          Hour = 4;
          Minute = 30;
        } # Sunday 4:30 AM
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
    vulnix # CVE scanner for Nix packages

    # File integrity and encryption
    age # Modern encryption tool
    sops # Secrets management

    # Network security
    nmap # Network discovery and security auditing

    # System monitoring
    htop # Process monitoring
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
