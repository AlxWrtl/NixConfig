{ config, pkgs, lib, inputs, ... }:

{
  # Core system configuration

  # Nix configuration
  nix = {
    settings = {
      # Enable flakes and new nix command
      experimental-features = [ "nix-command" "flakes" ];

      # Build users optimization
      build-users-group = "nixbld";
      max-jobs = "auto";

      # Trusted users
      trusted-users = [ "root" "alexandrewertel" ];

      # Keep outputs and derivations for better development experience
      keep-outputs = true;
      keep-derivations = true;

      # Auto-optimize store
      auto-optimise-store = true;

      # Binary caches
      substituters = [
        "https://cache.nixos.org/"
        "https://nix-community.cachix.org"
      ];
      trusted-public-keys = [
        "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
    };

    # Enable garbage collection
    gc = {
      automatic = true;
      interval.Day = 7;
      options = "--delete-older-than 7d";
    };

    # Nix package
    package = pkgs.nix;
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
    LESS = "-R";
  };
}