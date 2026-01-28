{
  config,
  pkgs,
  lib,
  ...
}:

{
  # ============================================================================
  # HOME MANAGER USER CONFIGURATION
  # ============================================================================
  # Modern user-level configuration managed by home-manager
  # This separates user settings from system settings for better modularity

  imports = [
    ./options.nix # Feature toggles
    ./zsh.nix # Zsh shell configuration
    ./git.nix # Git version control configuration
    ./claude-code.nix # Claude Code integration
  ];

  # === Basic Configuration ===
  home.username = "alx";
  home.homeDirectory = "/Users/alx";
  home.stateVersion = "24.11";

  home.sessionVariables = {
    CLAUDE_CONFIG_DIR = "$HOME/.claude";
  };

  # === Allow Home Manager to manage itself ===
  programs.home-manager.enable = true;

  # ============================================================================
  # USER PACKAGES
  # ============================================================================
  # Packages are managed via home/options.nix feature flags
  # Override via: home-features.devTools = false;


  # ============================================================================
  # XDG DIRECTORIES
  # ============================================================================

  xdg = {
    enable = true;
    # Note: userDirs is Linux-only, macOS uses standard directories
  };

  # ============================================================================
  # USER FONTS
  # ============================================================================

  fonts.fontconfig.enable = true;

}
