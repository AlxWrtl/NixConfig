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
  # DISABLED: Redundant with App Store updates + manual vulnix

  # === Security update notifications ===
  # DISABLED: Redundant with nix-flake-update

  # ============================================================================
  # SYSTEM SECURITY HARDENING
  # ============================================================================

  # === Enhanced file system security ===
  # DISABLED: One-time boot config sufficient, not needed as periodic service

  # ============================================================================
  # SECURITY MONITORING
  # ============================================================================

  # === Log rotation for security logs ===
  # DISABLED: macOS handles log rotation natively

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
