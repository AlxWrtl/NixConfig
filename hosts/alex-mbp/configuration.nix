{ config, pkgs, lib, inputs, ... }:

{
  # ============================================================================
  # HOST CONFIGURATION: ALEXANDRE'S MACBOOK PRO
  # ============================================================================
  # Host-specific settings for alex-mbp
  # Hardware-specific, networking, and unique identification settings

  # ============================================================================
  # SYSTEM IDENTIFICATION & NETWORKING
  # ============================================================================

  # === Network Identity ===
  networking = {
    computerName = "Alexandre's MacBook Pro";             # Display name in System Preferences
    hostName = "alex-mbp";                               # System hostname for network identification
    localHostName = "alex-mbp";                          # Bonjour/mDNS local hostname
  };

  # ============================================================================
  # PLATFORM & ARCHITECTURE
  # ============================================================================

  # === Target Platform ===
  nixpkgs.hostPlatform = "aarch64-darwin";               # Apple Silicon (M1/M2/M3) macOS target

  # ============================================================================
  # USER ACCOUNT CONFIGURATION
  # ============================================================================

  # === Primary User Account ===
  users.users.alx = {
    name = "alx";                                        # Username for system identification
    home = "/Users/alx";                                 # User home directory path
  };

  # ============================================================================
  # SYSTEM VERSIONING & COMPATIBILITY
  # ============================================================================

  # === System State Version ===
  system.stateVersion = 5;                              # nix-darwin compatibility version (don't change)

  # === Configuration Revision Tracking ===
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # ============================================================================
  # NIXPKGS CONFIGURATION OVERRIDES
  # ============================================================================

  # === Package Permissions (Host Override) ===
  nixpkgs.config.allowUnfree = true;                    # Enable proprietary packages (VSCode, Slack, etc.)

  # ============================================================================
  # HOST-SPECIFIC NOTES
  # ============================================================================
  #
  # This configuration file contains only host-specific settings:
  # - Network identification and hostname
  # - Hardware platform specification  
  # - User account definitions
  # - System versioning and compatibility
  #
  # All other system configuration is handled by modules:
  # - Core system settings → modules/system.nix
  # - UI/UX preferences → modules/ui.nix
  # - Development tools → modules/development.nix
  # - Shell configuration → modules/shell.nix
  # - Package management → modules/packages.nix & modules/brew.nix
  # - Fonts → modules/fonts.nix
  #
  # Benefits of this modular approach:
  # - Easy to add new hosts by copying this file
  # - Shared configuration across multiple machines
  # - Clear separation of concerns
  # - Simplified maintenance and updates
  #
}