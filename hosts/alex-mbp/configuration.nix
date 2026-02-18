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

  environment.systemPackages = [
  ];
}