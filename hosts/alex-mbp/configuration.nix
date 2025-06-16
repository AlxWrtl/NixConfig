{ config, pkgs, lib, inputs, ... }:

{
  # Host-specific configuration for Alexandre's MacBook Pro

  # Hostname configuration
  networking.computerName = "Alexandre's MacBook Pro";
  networking.hostName = "alex-mbp";
  networking.localHostName = "alex-mbp";

  # User configuration
  users.users.alexandrewertel = {
    name = "alexandrewertel";
    home = "/Users/alexandrewertel";
  };

  # The platform the configuration will be used on
  nixpkgs.hostPlatform = "aarch64-darwin";

  # System state version for backwards compatibility
  system.stateVersion = 5;

  # Allow unfree packages (for VSCode, etc.)
  nixpkgs.config.allowUnfree = true;

  # Enable necessary system features
  security.pam.enableSudoTouchIdAuth = true;
  services.nix-daemon.enable = true;

  # Set Git commit hash for darwin-version
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # macOS-specific system preferences (minimal in host config)
  system.defaults = {
    dock = {
      orientation = "left";
      autohide = true;
    };
    NSGlobalDomain = {
      AppleInterfaceStyle = "Dark";
    };
  };
}