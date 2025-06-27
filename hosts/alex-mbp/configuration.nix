{ config, pkgs, lib, inputs, ... }:

{
  # Host-specific configuration for Alexandre's MacBook Pro

  # Hostname configuration
  networking.computerName = "Alexandre's MacBook Pro";
  networking.hostName = "alex-mbp";
  networking.localHostName = "alex-mbp";

  # User configuration
  users.users.alx = {
    name = "alx";
    home = "/Users/alx";
  };

  # The platform the configuration will be used on
  nixpkgs.hostPlatform = "aarch64-darwin";

  # System state version for backwards compatibility
  system.stateVersion = 5;

  # Allow unfree packages (for VSCode, etc.)
  nixpkgs.config.allowUnfree = true;

  # Set Git commit hash for darwin-version
  system.configurationRevision = inputs.self.rev or inputs.self.dirtyRev or null;

  # NOTE: system.defaults options are temporarily disabled because they require system.primaryUser
  # which is not available in this version of nix-darwin. These can be re-enabled after updating.
}