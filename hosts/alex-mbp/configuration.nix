{ config, pkgs, lib, inputs, ... }:

{
  # Host-specific settings for alex-mbp

  networking = {
    computerName = "Alexandre's MacBook Pro";
    hostName = "alex-mbp";
    localHostName = "alex-mbp";
  };

  nixpkgs.hostPlatform = "aarch64-darwin";

  users.users.alx = {
    name = "alx";
    home = "/Users/alx";
  };

  system.stateVersion = 5;
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = [
    # Use homebrew for macOS-native trash utility via brew.nix
  ];

  # Automated cleanup of removed app data
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