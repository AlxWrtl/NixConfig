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
  # APP CLEANUP AUTOMATION
  # ============================================================================

  # === Cleanup Tools ===
  environment.systemPackages = with pkgs; [
    # Use homebrew for macOS-native trash utility via brew.nix
  ];

  # === Automated App Data Cleanup ===
  system.activationScripts.cleanupRemovedApps.text = ''
    echo "Cleaning orphaned app data..."
    CURRENT_CASKS="${builtins.concatStringsSep " " (builtins.map (c: c.name or c) config.homebrew.casks)}"
    CASK_HISTORY="/var/lib/nix-darwin/cask-history"
    
    # Create directory if it doesn't exist
    mkdir -p "$(dirname "$CASK_HISTORY")"
    
    if [[ -f "$CASK_HISTORY" ]]; then
      comm -23 <(sort "$CASK_HISTORY") <(echo "$CURRENT_CASKS" | tr ' ' '\n' | sort) | while read removed; do
        if [[ -n "$removed" ]]; then
          echo "Removing data for: $removed"
          trash ~/Library/Preferences/*"$removed"* 2>/dev/null || true
          trash ~/Library/Application\ Support/*"$removed"* 2>/dev/null || true  
          trash ~/Library/Caches/*"$removed"* 2>/dev/null || true
        fi
      done
    fi
    
    echo "$CURRENT_CASKS" | tr ' ' '\n' > "$CASK_HISTORY"
  '';
}