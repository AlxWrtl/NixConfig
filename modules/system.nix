{ config, pkgs, lib, inputs, ... }:

{
  # Core system configuration

  # Nix configuration
  # FIXED: Re-enable nix-darwin's module management while preserving Determinate installer settings
  nix = {
    # Allow nix-darwin to manage services and integrations (like Homebrew)
    enable = true;

    # Basic settings that work with Determinate installer
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };

    # Store optimization
    optimise.automatic = true;

    # Weekly garbage collection
    gc = {
      automatic = true;
      interval = { Weekday = 7; }; # Sunday
      options = "--delete-older-than 7d";
    };
  };

  # nixpkgs configuration
  nixpkgs.config = {
    allowUnfree = lib.mkDefault true;
    allowBroken = false;
    allowInsecure = false;
  };

  # System environment variables
  environment.variables = {
    EDITOR = "nvim";
    VISUAL = "nvim";
    PAGER = "less";
  };

  # System user configuration - required for homebrew and other user-specific options
  system.primaryUser = "alx";

  # === SECURITY CONFIGURATION ===
  # Enable TouchID for sudo authentication (updated syntax)
  security.pam.services.sudo_local.touchIdAuth = true;

  # === SYSTEM DEFAULTS ===
  # Configure trackpad and input settings
  system.defaults = {
    # Trackpad settings
    trackpad = {
      TrackpadRightClick = true; # Enable two-finger right-click
      Clicking = true; # Enable tap to click
      TrackpadThreeFingerDrag = true; # Enable three finger drag
    };

    # Global system settings
    NSGlobalDomain = {
      # Optional: Natural scrolling (uncomment if you want it)
      # "com.apple.swipescrolldirection" = true;
    };

    # Disable Gatekeeper warnings for downloaded apps
    SoftwareUpdate = {
      AutomaticallyInstallMacOSUpdates = false;
    };
    
    # Disable quarantine for downloaded applications
    LaunchServices = {
      LSQuarantine = false;
    };
  };
}