{ config, pkgs, lib, inputs, ... }:

{
  # === CORE SYSTEM PACKAGES CONFIGURATION ===
  # Essential system utilities and tools (non-development focused)

  environment.systemPackages = with pkgs; [

    # === SHELL & TERMINAL ENHANCEMENTS ===
    # Modern replacements for standard tools
    zsh                 # Z shell
    starship            # Modern shell prompt
    zsh-autosuggestions # Command autosuggestions
    zsh-syntax-highlighting # Syntax highlighting

    # Navigation & file management (modern alternatives)
    zoxide              # Smart directory jumper (cd replacement)
    fzf                 # Fuzzy finder
    eza                 # Modern ls replacement (better colors/icons)
    bat                 # Cat with syntax highlighting
    tree                # Directory tree viewer
    fd                  # Find alternative (faster)
    ripgrep             # Grep alternative (faster)

    # File operations
    rsync               # File synchronization

    # History & session management
    atuin               # Shell history manager (better than Ctrl+R)

    # === NETWORK & SYSTEM TOOLS ===
    btop                # Modern system monitor
    neofetch            # System information
  ];

    # === NIX PACKAGE MANAGER OPTIMIZATIONS ===
  nix.settings = {
    # Enable flakes and new command interface
    experimental-features = [ "nix-command" "flakes" ];

    # Optimize builds
    max-jobs = "auto";              # Use all CPU cores
    cores = 0;                      # Use all CPU cores per job

    # Binary cache optimization
    substituters = [
      "https://cache.nixos.org/"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];
  };

  # Note: Store optimization and garbage collection are configured in modules/system.nix

  # === GLOBAL PACKAGE CONFIGURATION ===
  nixpkgs.config = {
    # Enable unfree packages globally
    allowUnfree = true;

    # Package-specific configurations
    permittedInsecurePackages = [
      # Add any required insecure packages here
    ];
  };

  # === OVERLAYS (for package customizations) ===
  nixpkgs.overlays = [
    # Add custom overlays here if needed
    # Example: (self: super: { ... })
  ];
}