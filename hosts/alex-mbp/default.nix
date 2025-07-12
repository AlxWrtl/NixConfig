{ config, pkgs, lib, inputs, ... }:

{
  # ============================================================================
  # HOST MODULE: ALEX-MBP
  # ============================================================================
  # Centralized host configuration module for Alexandre's MacBook Pro
  # This module imports and orchestrates host-specific configuration

  # ============================================================================
  # HOST CONFIGURATION IMPORTS
  # ============================================================================

  imports = [
    # === Host-Specific Configuration ===
    ./configuration.nix                                 # Core host settings (networking, users, platform)
  ];

  # ============================================================================
  # HOST MODULE ORGANIZATION
  # ============================================================================
  #
  # This default.nix serves as the entry point for alex-mbp host configuration:
  #
  # Structure:
  # hosts/alex-mbp/
  # ├── default.nix           # This file - module orchestration
  # └── configuration.nix     # Core host settings
  #
  # Benefits:
  # - Clean separation between host identification and host modules
  # - Follows the same pattern as the modules/ directory
  # - Simplifies flake.nix by having a single import per host
  #
  # Usage in flake.nix:
  # modules = [ ./hosts/alex-mbp ./modules/system.nix ... ];
  #
}