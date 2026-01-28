{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
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
}
