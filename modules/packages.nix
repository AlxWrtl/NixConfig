{
  config,
  pkgs,
  lib,
  inputs,
  ...
}:

{
  # Core system packages configuration
  # Essential utilities and modern CLI tools for daily system use
  # Development-specific packages are in development.nix

  # ============================================================================
  # SYSTEM PACKAGES
  # ============================================================================

  environment.systemPackages = with pkgs; [

    # === SHELL & TERMINAL ENHANCEMENTS ===
    zsh # Z shell (primary shell)
    starship # Modern cross-shell prompt
    zsh-autosuggestions # Fish-like autosuggestions for zsh
    zsh-fast-syntax-highlighting # Optimized syntax highlighting

    # === MODERN CLI REPLACEMENTS ===
    # Enhanced versions of standard UNIX tools
    eza # Modern 'ls' with colors and icons
    bat # 'cat' with syntax highlighting and git integration
    fd # Modern 'find' - faster and more user-friendly
    ripgrep # Modern 'grep' - incredibly fast search
    tree # Directory structure visualization

    # === NAVIGATION & SEARCH ===
    zoxide # Smart 'cd' - learns your patterns
    fzf # Fuzzy finder for files, history, processes
    atuin # Enhanced shell history with sync

    # === FILE OPERATIONS ===
    rsync # Efficient file synchronization

    # === SYSTEM MONITORING & INFO ===
    btop # Modern system monitor (htop replacement)
    fastfetch # System information display (neofetch replacement)
  ];

  # Note: Nix configuration is handled comprehensively in modules/system.nix

  # ============================================================================
  # PACKAGE CONFIGURATION
  # ============================================================================

  nixpkgs.config = {
    # === Package Permissions ===
    allowUnfree = true; # Enable proprietary packages (VS Code, etc.)

    # === Security Exceptions ===
    permittedInsecurePackages = [
      # Add specific packages here if needed for compatibility
      # Example: "package-version"
    ];
  };

  # ============================================================================
  # PACKAGE OVERLAYS
  # ============================================================================
  # Custom package modifications and additions

  nixpkgs.overlays = [
    # Add custom overlays here for package customizations
    # Example: (self: super: {
    #   myPackage = super.myPackage.overrideAttrs (oldAttrs: {
    #     # Custom modifications
    #   });
    # })
  ];

  # Note: Store optimization and garbage collection are configured in system.nix
}
